#!/usr/bin/env python3
"""Confere que os símbolos do OpenCV usados pelo código existem nesta máquina.

Por que isso existe
-------------------
Pinar a versão do OpenCV resolve *a maior parte* do problema, mas não tudo: os
perfis do time rodam em Ubuntu 22.04 (Python 3.10) e 24.04 (Python 3.12), e na
Jetson pode ser necessário o build com CUDA do JetPack. Ou seja, em alguns
casos as versões vão divergir legitimamente entre máquinas.

O que NÃO pode divergir é a API que o nosso código chama. Este script é a rede
de segurança final: ele varre o código, extrai todo símbolo `cv2.X` e
`cv2.aruco.X` que aparece, e confirma que cada um existe no OpenCV instalado.

Ele pega a classe de bug que já custou caro ao time: a API do ArUco mudou de
forma incompatível entre OpenCV 4.6 e 4.7 (`DetectorParameters_create()` virou
`DetectorParameters()`), e o sintoma era ter que editar o código à mão depois
de subir para o drone.

Varrer em vez de manter uma lista fixa é proposital: código novo entra na
checagem sozinho, sem ninguém lembrar de atualizar nada.

A varredura usa a AST do Python, não expressão regular: assim ela enxerga
acesso de atributo de verdade e ignora o que aparece dentro de string,
comentário ou docstring — inclusive as deste arquivo.

Uso
---
    python3 env/cv_api_contract.py             # varre ./src
    python3 env/cv_api_contract.py --src PATH  # varre outro diretório

Sai 0 se todos os símbolos existem, 1 se algum falta.
"""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path

# Diretórios que não são código nosso.
_SKIP = {"build", "install", "log", ".git", "__pycache__", "node_modules"}


class _Visitor(ast.NodeVisitor):
    """Coleta acessos de atributo em cv2 e seus submódulos.

    Entende as formas que o código do time usa:
        import cv2                      -> cv2.foo, cv2.aruco.foo
        import cv2.aruco as aruco       -> aruco.foo
        from cv2 import aruco           -> aruco.foo
    """

    def __init__(self) -> None:
        # nome local -> caminho real do módulo
        self.aliases: dict[str, str] = {"cv2": "cv2"}
        self.used: dict[str, set[str]] = {}
        # Símbolos que o código já trata como possivelmente ausentes.
        self.guarded: dict[str, set[str]] = {}

    # --- imports ---------------------------------------------------------
    def visit_Import(self, node: ast.Import) -> None:
        for a in node.names:
            if a.name == "cv2" or a.name.startswith("cv2."):
                self.aliases[a.asname or a.name] = a.name
        self.generic_visit(node)

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        if node.module and (node.module == "cv2" or node.module.startswith("cv2.")):
            for a in node.names:
                self.aliases[a.asname or a.name] = f"{node.module}.{a.name}"
        self.generic_visit(node)

    # --- uso -------------------------------------------------------------
    def _module_of(self, node: ast.AST) -> str | None:
        """Resolve o caminho do módulo de uma expressão, se for um módulo cv2."""
        if isinstance(node, ast.Name):
            return self.aliases.get(node.id)
        if isinstance(node, ast.Attribute):
            base = self._module_of(node.value)
            if base is None:
                return None
            candidate = f"{base}.{node.attr}"
            # Só desce se for um submódulo que conhecemos de fato.
            return candidate if candidate == "cv2.aruco" else None
        return None

    def visit_Attribute(self, node: ast.Attribute) -> None:
        module = self._module_of(node.value)
        if module is not None:
            self.used.setdefault(module, set()).add(node.attr)
        self.generic_visit(node)

    # --- guardas de compatibilidade --------------------------------------
    # Código que já trata a ausência do símbolo em tempo de execução não está
    # violando o contrato — está fazendo exatamente a coisa certa. As duas
    # formas abaixo aparecem no código do time.

    def visit_Call(self, node: ast.Call) -> None:
        # if hasattr(aruco, 'DetectorParameters_create'): ...
        if (
            isinstance(node.func, ast.Name)
            and node.func.id == "hasattr"
            and len(node.args) == 2
            and isinstance(node.args[1], ast.Constant)
            and isinstance(node.args[1].value, str)
        ):
            module = self._module_of(node.args[0])
            if module is not None:
                self.guarded.setdefault(module, set()).add(node.args[1].value)
        self.generic_visit(node)

    def visit_Try(self, node: ast.Try) -> None:
        # try: ... except AttributeError: <usa a API antiga>
        catches_attr_error = any(
            (isinstance(h.type, ast.Name) and h.type.id == "AttributeError")
            or (
                isinstance(h.type, ast.Tuple)
                and any(
                    isinstance(e, ast.Name) and e.id == "AttributeError"
                    for e in h.type.elts
                )
            )
            for h in node.handlers
        )
        if catches_attr_error:
            for child in ast.walk(node):
                if isinstance(child, ast.Attribute):
                    module = self._module_of(child.value)
                    if module is not None:
                        self.guarded.setdefault(module, set()).add(child.attr)
        self.generic_visit(node)


def scan(src: Path) -> tuple[dict[str, set[str]], int]:
    """Devolve ({módulo: {símbolos exigidos}}, nº de símbolos com guarda).

    Símbolos protegidos por `hasattr` ou `try/except AttributeError` são
    descontados: o código já lida com a ausência deles.
    """
    required: dict[str, set[str]] = {}
    n_guarded = 0

    for path in sorted(src.rglob("*.py")):
        if _SKIP & set(path.parts):
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="ignore"), str(path))
        except (OSError, SyntaxError):
            # Arquivo ilegível ou de outra versão de Python: não é motivo para
            # reprovar o contrato, só não dá para checá-lo.
            continue

        visitor = _Visitor()
        visitor.visit(tree)

        # A guarda vale SÓ no arquivo em que aparece. Um `hasattr` num módulo
        # não protege outro módulo que chama o mesmo símbolo sem checar —
        # tratar isso globalmente esconderia exatamente o bug que procuramos.
        for module, names in visitor.used.items():
            if module == "cv2":
                names = names - {"aruco"}  # submódulo, não atributo a checar
            safe = visitor.guarded.get(module, set())
            n_guarded += len(names & safe)
            if remaining := (names - safe):
                required.setdefault(module, set()).update(remaining)

    return required, n_guarded


def resolve(module_path: str):
    """Importa cv2 e desce até o submódulo pedido. Devolve None se não existir."""
    import cv2

    obj = cv2
    for part in module_path.split(".")[1:]:
        obj = getattr(obj, part, None)
        if obj is None:
            return None
    return obj


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--src",
        default=str(Path(__file__).resolve().parent.parent / "src"),
        help="diretório a varrer (padrão: <raiz do workspace>/src)",
    )
    args = parser.parse_args()

    src = Path(args.src)
    if not src.is_dir():
        print(f"AVISO: {src} não existe — nada a checar.")
        print("       (normal antes do primeiro `vcs import`)")
        return 0

    try:
        import cv2
    except ImportError:
        print("ERRO: cv2 não pôde ser importado.", file=sys.stderr)
        print("      Instale o OpenCV do perfil: veja env/<perfil>.yaml", file=sys.stderr)
        return 1

    used, n_guarded = scan(src)
    total = sum(len(v) for v in used.values())
    if total == 0:
        print(f"Nenhum uso de cv2 encontrado em {src}.")
        return 0

    missing: list[str] = []
    for module_path, names in sorted(used.items()):
        mod = resolve(module_path)
        if mod is None:
            missing.extend(f"{module_path}.{n}" for n in sorted(names))
            continue
        missing.extend(f"{module_path}.{n}" for n in sorted(names) if not hasattr(mod, n))

    guard_note = (
        f"  ({n_guarded} com guarda de compatibilidade, não exigidos)"
        if n_guarded
        else ""
    )
    print(
        f"OpenCV {cv2.__version__} — {total - len(missing)}/{total} "
        f"símbolos exigidos presentes{guard_note}"
    )

    if not missing:
        print("Contrato de API do OpenCV: OK")
        return 0

    print()
    print(f"FALTAM {len(missing)} símbolo(s) que o código chama:")
    for name in missing:
        print(f"  - {name}")
    print()
    print(
        "Cada um destes é um AttributeError em tempo de execução, no drone, no\n"
        "meio da missão — não em tempo de build. Ou a versão do OpenCV está\n"
        "errada para este perfil, ou o código usa uma API que foi removida e\n"
        "precisa ser migrada."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
