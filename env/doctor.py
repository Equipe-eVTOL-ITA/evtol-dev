#!/usr/bin/env python3
"""Verifica a máquina atual contra um perfil de ambiente do eVTOL ITA.

Um `.repos` pina código. Este script pina o resto: distro do ROS, versão do
Gazebo, variante do bridge, PX4, apt e pip. É o que impede que uma diferença
de ambiente vire um bug silencioso de horas.

Uso normal via ./doctor.sh na raiz do workspace.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "ERRO: PyYAML nao encontrado.\n"
        "      Instale com: sudo apt install python3-yaml"
    )

ENV_DIR = Path(__file__).resolve().parent
_REPO_ROOT = ENV_DIR.parent

# Normalmente o evtol-dev E a raiz do workspace. No layout antigo ele fica em
# <ws>/src/evtol-dev/. O sinal e o diretorio pai se chamar `src` -- e nao a
# existencia de `src/` aqui dentro, que numa raiz recem-clonada ainda nao
# existe (e gitignorado e criado pelo vcs import).
WS_ROOT = _REPO_ROOT.parent.parent if _REPO_ROOT.parent.name == "src" else _REPO_ROOT

# --------------------------------------------------------------------------- #
# Saida
# --------------------------------------------------------------------------- #

_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


GREEN, RED, YELLOW, BOLD, DIM = "32", "31", "33", "1", "2"


class Report:
    """Acumula resultados e decide o codigo de saida."""

    def __init__(self) -> None:
        self.failures: list[tuple[str, str, str]] = []  # (item, detalhe, fix)
        self.warnings: list[tuple[str, str]] = []
        self.passed = 0

    def ok(self, item: str, detail: str = "") -> None:
        self.passed += 1
        suffix = f"  {_c(DIM, detail)}" if detail else ""
        print(f"  {_c(GREEN, 'OK  ')} {item}{suffix}")

    def fail(self, item: str, detail: str, fix: str = "") -> None:
        self.failures.append((item, detail, fix))
        print(f"  {_c(RED, 'FALHA')} {item}")
        for line in detail.strip().splitlines():
            print(f"        {line.strip()}")
        if fix:
            print(f"        {_c(BOLD, 'corrija:')} {fix}")

    def warn(self, item: str, detail: str) -> None:
        self.warnings.append((item, detail))
        print(f"  {_c(YELLOW, 'AVISO')} {item}")
        for line in detail.strip().splitlines():
            print(f"        {line.strip()}")


def section(title: str) -> None:
    print(f"\n{_c(BOLD, title)}")


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def run(cmd: list[str] | str, cwd: str | Path | None = None) -> tuple[int, str]:
    """Executa um comando e devolve (returncode, stdout+stderr strip)."""
    try:
        proc = subprocess.run(
            cmd,
            shell=isinstance(cmd, str),
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return 1, str(exc)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def apt_version(pkg: str) -> str | None:
    """Versao instalada do pacote, ou None se nao estiver instalado."""
    rc, out = run(["dpkg-query", "-W", "-f=${Status}\t${Version}", pkg])
    if rc != 0 or "\t" not in out:
        return None
    status, version = out.split("\t", 1)
    if "install ok installed" not in status:
        return None
    return version.strip()


def pip_version(pkg: str) -> str | None:
    from importlib import metadata

    try:
        return metadata.version(pkg)
    except metadata.PackageNotFoundError:
        return None


_SPECIFIER_RE = re.compile(r"^\s*(==|!=|<=|>=|<|>|~=)")


def is_specifier(expected: str) -> bool:
    """True se o valor esperado for uma restrição de versão (ex.: '<80')."""
    return bool(_SPECIFIER_RE.match(str(expected)))


def matches(actual: str, expected: str) -> bool:
    """Compara a versão observada com a esperada.

    Aceita duas formas:
      - glob      "0.244.*"   — casa texto, bom para versões do apt, que não
                                seguem PEP 440 (ex.: '0.244.11-1002jammy').
      - restrição "<80", ">=1.26,<2" — comparação numérica de verdade, para
                                quando o que importa é uma faixa e não um valor.
    """
    expected = "" if expected is None else str(expected).strip()
    if expected in ("*", ""):
        return True

    if is_specifier(expected):
        try:
            from packaging.specifiers import SpecifierSet
            from packaging.version import InvalidVersion, Version

            try:
                return Version(actual) in SpecifierSet(expected)
            except InvalidVersion:
                # Versões do apt frequentemente não são PEP 440. Nesse caso a
                # restrição não é aplicável — melhor não afirmar nada do que
                # afirmar errado.
                return True
        except ImportError:
            return True

    return fnmatch.fnmatch(actual, expected)


def install_hint(pkg: str, expected: str) -> str:
    """Comando de instalação correto para a forma do valor esperado."""
    expected = str(expected).strip()
    if is_specifier(expected):
        return f"pip install '{pkg}{expected}'"
    return f"pip install '{pkg}=={expected}'"


# --------------------------------------------------------------------------- #
# Checks
# --------------------------------------------------------------------------- #


def check_os(spec: dict, rep: Report) -> None:
    if not spec:
        return
    section("Sistema operacional")

    if (want := spec.get("distributor_id")) or (want_rel := spec.get("release")):
        rc, distro = run(["lsb_release", "-is"])
        rc2, release = run(["lsb_release", "-rs"])
        if rc != 0 or rc2 != 0:
            rep.warn("lsb_release", "nao disponivel; pulando checagem de SO")
        else:
            want_rel = spec.get("release")
            if want and distro != want:
                rep.fail("distribuicao", f"esperado {want}, encontrado {distro}")
            elif want_rel and release != want_rel:
                rep.fail(
                    "versao do Ubuntu",
                    f"esperado {want_rel}, encontrado {release}\n"
                    "Perfis do eVTOL sao amarrados a versao do Ubuntu porque o "
                    "ROS e o Gazebo sao distribuidos por ela.",
                    fix=f"use o perfil correspondente ao Ubuntu {release} "
                    "(./doctor.sh --list)",
                )
            else:
                rep.ok("SO", f"{distro} {release}")

    if want_py := spec.get("python"):
        actual = f"{sys.version_info.major}.{sys.version_info.minor}"
        if actual != want_py:
            rep.fail(
                "Python",
                f"esperado {want_py}, encontrado {actual}\n"
                "Pacotes pip compilados nao sao intercambiaveis entre versoes "
                "de Python.",
            )
        else:
            rep.ok("Python", actual)


def check_ros(spec: dict, rep: Report) -> None:
    if not (want := (spec or {}).get("distro")):
        return
    section("ROS 2")

    setup = Path(f"/opt/ros/{want}/setup.bash")
    if not setup.exists():
        rep.fail(
            f"ROS 2 {want}",
            f"nao instalado ({setup} nao existe)",
            fix=f"sudo apt install ros-{want}-desktop  (veja docs/SETUP.md)",
        )
        return
    rep.ok(f"ROS 2 {want} instalado", str(setup))

    active = os.environ.get("ROS_DISTRO")
    if active is None:
        rep.warn(
            "ROS_DISTRO",
            "nao definido no shell atual — voce provavelmente esqueceu de rodar\n"
            f"  source /opt/ros/{want}/setup.bash",
        )
    elif active != want:
        rep.fail(
            "ROS_DISTRO",
            f"o shell atual esta com '{active}', mas este perfil exige '{want}'.\n"
            "Compilar ou executar com o distro errado gera erros que NAO apontam\n"
            "para a causa real. Este e o modo de falha que o perfil existe para pegar.",
            fix=f"abra um shell limpo e rode: source /opt/ros/{want}/setup.bash",
        )
    else:
        rep.ok("ROS_DISTRO ativo", active)


def check_apt(spec: dict, rep: Report) -> None:
    if not spec:
        return
    required = spec.get("required") or {}
    forbidden = spec.get("forbidden") or {}

    if required:
        section("Pacotes apt obrigatorios")
        for pkg, want in sorted(required.items()):
            want = "*" if want is None else str(want)
            actual = apt_version(pkg)
            if actual is None:
                rep.fail(pkg, "nao instalado", fix=f"sudo apt install {pkg}")
            elif not matches(actual, want):
                rep.fail(
                    pkg,
                    f"versao {actual} nao casa com o esperado '{want}'",
                    fix=f"sudo apt install --allow-downgrades {pkg}={want}",
                )
            else:
                rep.ok(pkg, actual)

    if forbidden:
        section("Pacotes apt proibidos (conflitantes)")
        for pkg, reason in sorted(forbidden.items()):
            actual = apt_version(pkg)
            if actual is None:
                rep.ok(f"{pkg} ausente")
            else:
                rep.fail(
                    f"{pkg} INSTALADO ({actual})",
                    str(reason),
                    fix=f"sudo apt remove {pkg}",
                )


def check_pip(spec: dict, rep: Report) -> None:
    if not spec:
        return
    required = spec.get("required") or {}
    forbidden = spec.get("forbidden") or {}

    if required:
        section("Pacotes pip obrigatorios")
        for pkg, want in sorted(required.items()):
            want = "*" if want is None else str(want)
            actual = pip_version(pkg)
            if actual is None:
                rep.fail(pkg, "nao instalado", fix=install_hint(pkg, want))
            elif not matches(actual, want):
                rep.fail(
                    pkg,
                    f"versao {actual} nao casa com o esperado '{want}'",
                    fix=install_hint(pkg, want),
                )
            else:
                rep.ok(pkg, f"{actual}  (exigido: {want})")

    if forbidden:
        section("Pacotes pip proibidos (conflitantes)")
        for pkg, reason in sorted(forbidden.items()):
            actual = pip_version(pkg)
            if actual is None:
                rep.ok(f"{pkg} ausente")
            else:
                rep.fail(
                    f"{pkg} INSTALADO ({actual})",
                    str(reason),
                    fix=f"pip uninstall -y {pkg}",
                )


def check_commands(spec: dict, rep: Report) -> None:
    if not spec:
        return
    section("Binarios no PATH")
    from shutil import which

    for name, cfg in sorted(spec.items()):
        cfg = cfg or {}
        path = which(name)
        if path is None:
            rep.fail(name, "nao encontrado no PATH", fix=cfg.get("fix", ""))
            continue

        if (want_path := cfg.get("expect_path")) and path != want_path:
            rep.warn(
                name,
                f"encontrado em {path}, esperado em {want_path} "
                "(pode ser uma segunda instalacao sombreando a correta)",
            )
            continue

        want_version = cfg.get("expect_version")
        if not want_version:
            rep.ok(name, path)
            continue

        rc, out = run(cfg.get("version_cmd", f"{name} --version"))
        match = re.search(cfg.get("version_regex", r"(\d+\.\d+\.\d+)"), out)
        if not match:
            rep.warn(name, f"nao consegui extrair a versao de: {out.splitlines()[:1]}")
        elif not matches(match.group(1), want_version):
            rep.fail(
                name,
                f"versao {match.group(1)} nao casa com o esperado '{want_version}'",
                fix=cfg.get("fix", ""),
            )
        else:
            rep.ok(name, match.group(1))


def check_python_build(spec: dict, rep: Report) -> None:
    """Testa DE VERDADE se a maquina instala um pacote ament_python.

    Uma checagem de versao nao consegue expressar esta restricao, porque ela e
    uma RELACAO entre setuptools e packaging:

        setuptools <= 70.x   ok com o packaging 21.3 do Ubuntu 22.04
        setuptools 71 a 79   exige packaging >= 23
        setuptools >= 80     nao funciona (removeu --editable)

    Ja aconteceu de uma maquina passar nas 36 checagens e o build falhar no
    primeiro pacote por causa disso. Quando o que importa e um comportamento,
    teste o comportamento.
    """
    if not spec or not spec.get("check_python_build"):
        return
    section("Instalacao de pacote Python (teste funcional)")

    script = ENV_DIR / "build_smoke.py"
    if not script.exists():
        rep.warn("build_smoke.py", f"nao encontrado em {script}")
        return

    rc, out = run([sys.executable, str(script)])
    if rc == 0:
        rep.ok("colcon consegue instalar um pacote ament_python")
    else:
        rep.fail("colcon NAO consegue instalar um pacote ament_python", out)


def check_cv_api(spec: dict, rep: Report) -> None:
    """Roda o contrato de API do OpenCV, se o perfil pedir.

    Pinar a versao resolve a maior parte do problema, mas nao tudo: os perfis
    rodam em Python 3.10 e 3.12, e na Jetson pode ser necessario o build com
    CUDA do JetPack. O contrato e a rede final -- ele confere que os simbolos
    que o NOSSO codigo chama existem, mesmo quando as versoes divergem por
    motivo legitimo.
    """
    if not spec or not spec.get("check_opencv_api"):
        return
    section("Contrato de API do OpenCV")

    script = ENV_DIR / "cv_api_contract.py"
    if not script.exists():
        rep.warn("cv_api_contract.py", f"nao encontrado em {script}")
        return

    src = WS_ROOT / "src"
    if not src.is_dir():
        rep.warn("codigo-fonte", f"{src} nao existe — pulando (normal antes do primeiro import)")
        return

    rc, out = run([sys.executable, str(script), "--src", str(src)])
    first = out.splitlines()[0] if out else ""
    if rc == 0:
        rep.ok("simbolos do cv2 usados pelo codigo", first)
    else:
        rep.fail(
            "simbolos do cv2 usados pelo codigo",
            out,
            fix=f"python3 {script} --src {src}   (detalhes acima)",
        )


def check_git_repos(spec: dict, rep: Report) -> None:
    if not spec:
        return
    section("Repositorios externos ao workspace")
    for raw_path, cfg in sorted(spec.items()):
        cfg = cfg or {}
        path = Path(os.path.expanduser(raw_path))
        if not (path / ".git").exists():
            rep.fail(
                raw_path,
                f"nao e um repositorio git ({path} ausente ou sem .git)",
                fix=cfg.get("fix", "veja docs/SETUP.md"),
            )
            continue

        if want := cfg.get("expect_describe"):
            rc, out = run(["git", "describe", "--tags", "--always"], cwd=path)
            actual = out.splitlines()[0] if rc == 0 and out else "?"
            if not matches(actual, want):
                rep.fail(
                    raw_path,
                    f"em '{actual}', esperado '{want}'",
                    fix=cfg.get("fix", ""),
                )
            else:
                rep.ok(raw_path, actual)

        if want := cfg.get("expect_commit"):
            rc, out = run(["git", "rev-parse", "--short", "HEAD"], cwd=path)
            actual = out.splitlines()[0] if rc == 0 and out else "?"
            # Aceita prefixos: hashes curtos tem comprimentos diferentes por repo.
            if not (actual.startswith(want) or want.startswith(actual)):
                rep.fail(
                    raw_path,
                    f"no commit {actual}, esperado {want}",
                    fix=cfg.get("fix", ""),
                )
            else:
                rep.ok(raw_path, actual)


# --------------------------------------------------------------------------- #
# Selecao de perfil
# --------------------------------------------------------------------------- #


def available_profiles() -> list[str]:
    # Arquivos com "_" na frente sao BASES para herança, nao perfis
    # selecionaveis. Ver load_profile.
    return sorted(p.stem for p in ENV_DIR.glob("*.yaml") if not p.stem.startswith("_"))


def _deep_merge(base: dict, over: dict) -> dict:
    """
    Funde `over` sobre `base`, descendo em dicionarios aninhados.

    Chave presente nos dois: se ambas sao dicionario, funde; senao, `over`
    vence. Nao ha fusao de listas -- uma lista em `over` SUBSTITUI a de `base`,
    de proposito. Fundir listas tornaria impossivel a um perfil REMOVER um item
    herdado, e remover e justamente o que um perfil especializado precisa fazer.
    """
    saida = dict(base)
    for chave, valor in over.items():
        if (chave in saida and isinstance(saida[chave], dict)
                and isinstance(valor, dict)):
            saida[chave] = _deep_merge(saida[chave], valor)
        else:
            saida[chave] = valor
    return saida


def load_profile(name: str, _vistos: set | None = None) -> dict:
    """
    Carrega um perfil, resolvendo `extends` recursivamente.

    POR QUE HERANÇA EXISTE AQUI
    ---------------------------
    As maquinas do time diferem em pouco e coincidem em muito: mesma distro,
    mesmo ROS, mesmo pin de numpy, mesmos repositorios externos. Duplicar as
    ~300 linhas de justificativa medida entre dois arquivos garantiria que eles
    divergissem -- e divergencia silenciosa entre maquinas e exatamente o
    problema que este perfil existe para resolver. E o mesmo argumento que tirou
    o PidController de nove copias.

    Com `extends`, cada perfil declara SO O QUE O DISTINGUE, e a diferenca entre
    duas maquinas cabe na tela.
    """
    _vistos = _vistos or set()
    if name in _vistos:
        sys.exit(f"ERRO: ciclo de 'extends' no perfil '{name}'")
    _vistos.add(name)

    caminho = ENV_DIR / f"{name}.yaml"
    if not caminho.exists():
        sys.exit(f"ERRO: perfil '{name}' nao existe em {ENV_DIR}")

    spec = yaml.safe_load(caminho.read_text()) or {}
    if pai := spec.pop("extends", None):
        spec = _deep_merge(load_profile(pai, _vistos), spec)
    return spec


def resolve_profile(explicit: str | None) -> str:
    if explicit:
        return explicit

    marker = WS_ROOT / ".evtol-profile"
    if marker.exists():
        if name := marker.read_text().strip():
            return name

    sys.exit(
        "ERRO: nenhum perfil selecionado.\n\n"
        f"  Perfis disponiveis: {', '.join(available_profiles()) or '(nenhum)'}\n\n"
        "  Escolha um explicitamente:\n"
        "      ./doctor.sh --profile desktop-humble\n\n"
        "  Ou fixe o perfil desta maquina de uma vez por todas:\n"
        "      echo desktop-humble > .evtol-profile\n"
    )


# --------------------------------------------------------------------------- #


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verifica a maquina contra um perfil de ambiente do eVTOL ITA."
    )
    parser.add_argument("--profile", "-p", help="nome do perfil (ex.: desktop-humble)")
    parser.add_argument(
        "--list", "-l", action="store_true", help="lista os perfis disponiveis"
    )
    parser.add_argument(
        "--get",
        metavar="CAMPO",
        help="imprime um campo do perfil resolvido, ex.: --get ros.distro. "
        "Existe para que scripts de shell nao precisem ler o YAML por conta "
        "propria.",
    )
    args = parser.parse_args()

    # --get: uma saida legivel por shell.
    #
    # POR QUE ISTO EXISTE, e nao um `yaml.safe_load` em cada script.
    #
    # Antes da heranca, `ros_env.sh` e `setup.sh` liam o perfil com um
    # `yaml.safe_load` proprio, cada um com tres linhas de Python embutidas no
    # bash. Funcionava porque todo campo estava no mesmo arquivo.
    #
    # No dia em que `ros.distro` passou a vir de `_common-humble.yaml` por
    # `extends`, os dois pararam de encontra-lo -- e o sintoma foi TODA task do
    # VSCode falhando com "o perfil nao declara ros.distro". O doctor continuava
    # verde, porque so ele sabia resolver a heranca.
    #
    # A licao nao e "faltou testar as tasks": e que havia TRES implementacoes de
    # "ler o perfil" e so uma foi ensinada. Agora ha uma.
    if args.get:
        name = resolve_profile(args.profile)
        valor = load_profile(name)
        for parte in args.get.split("."):
            if not isinstance(valor, dict) or parte not in valor:
                sys.exit(
                    f"ERRO: o perfil '{name}' nao declara '{args.get}'."
                )
            valor = valor[parte]
        print(valor)
        return 0

    if args.list:
        print("Perfis disponiveis:")
        for name in available_profiles():
            data = yaml.safe_load((ENV_DIR / f"{name}.yaml").read_text()) or {}
            print(f"  {name:<20} {data.get('description', '')}")
        return 0

    name = resolve_profile(args.profile)
    path = ENV_DIR / f"{name}.yaml"
    if not path.exists():
        sys.exit(
            f"ERRO: perfil '{name}' nao existe.\n"
            f"      Disponiveis: {', '.join(available_profiles()) or '(nenhum)'}"
        )

    spec = load_profile(name)

    print(_c(BOLD, f"eVTOL ITA — verificacao de ambiente"))
    print(f"perfil:    {_c(BOLD, name)}")
    if desc := spec.get("description"):
        print(f"           {_c(DIM, desc)}")
    print(f"spec:      {path}")
    print(f"workspace: {WS_ROOT}")

    rep = Report()
    check_os(spec.get("os"), rep)
    check_ros(spec.get("ros"), rep)
    check_apt(spec.get("apt"), rep)
    check_pip(spec.get("pip"), rep)
    check_commands(spec.get("commands"), rep)
    check_git_repos(spec.get("git_repos"), rep)
    check_python_build(spec.get("pip"), rep)
    check_cv_api(spec.get("pip"), rep)

    print()
    if rep.failures:
        print(
            _c(
                RED,
                f"FALHOU: {len(rep.failures)} problema(s), "
                f"{rep.passed} checagem(ns) ok, {len(rep.warnings)} aviso(s).",
            )
        )
        print("\nProblemas encontrados:")
        for item, _, fix in rep.failures:
            print(f"  - {item}" + (f"\n      -> {fix}" if fix else ""))
        print(
            "\nCorrija os itens acima antes de compilar ou voar. Diferenca de\n"
            "ambiente e a classe de bug mais cara do time justamente porque nao\n"
            "aparece como erro — aparece como 'nao funciona e ninguem sabe por que'."
        )
        return 1

    print(
        _c(
            GREEN,
            f"OK: {rep.passed} checagem(ns) passaram, {len(rep.warnings)} aviso(s).",
        )
    )
    print(f"Ambiente confere com o perfil '{name}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
