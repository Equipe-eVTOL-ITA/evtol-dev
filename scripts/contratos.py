#!/usr/bin/env python3
"""Gera docs/CONTRATOS.md a partir do codigo, e reprova quando ele defasa.

O PROBLEMA QUE ISTO RESOLVE
---------------------------
As hipoteses que sustentam o voo -- convencoes de frame, nomes de topico,
frequencias, tamanho de imagem, como a ROI e feita, que comando do PX4 e usado
-- estavam todas documentadas, e todas documentadas NO LUGAR ONDE FORAM
ESCRITAS. Espalhadas por sessenta arquivos, em comentarios.

Na hora de depurar um voo de verdade nao havia onde olhar. E escrever um
documento unico so trocaria o problema de lugar: ele estaria certo por uma
semana e depois passaria a mentir, que e pior do que nao existir -- um
documento errado custa mais caro do que documento nenhum, porque as pessoas
confiam nele.

A SAIDA
-------
O documento nao e escrito: e DERIVADO. Duas fontes, as duas dentro do codigo:

  1. Fatos extraidos direto dos fontes -- topicos, QoS, timers, parametros dos
     YAML, comandos do PX4, e a tabela de onde se comanda movimento.

  2. Blocos-ancora, para a prosa que nao se gera. Um comentario delimitado
     assim, em qualquer arquivo:

         // >>> CONTRATO frames.camera-optical
         // imagem +x -> corpo +Y (direita) ...
         // <<< CONTRATO

     e transcrito para o documento. A explicacao continua onde quem programa
     trabalha; o documento e uma VISTA dela, nunca uma copia.

E o `--check` roda no CI. Mexeu no codigo e nao regenerou? O PR reprova. E a
mesma mecanica do sync_tasks.py, pela mesma razao.

Uso
---
    python3 scripts/contratos.py           # regenera docs/CONTRATOS.md
    python3 scripts/contratos.py --check   # so diz se esta desatualizado
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

WS_ROOT = Path(__file__).resolve().parent.parent
SRC = WS_ROOT / "src"
SAIDA = WS_ROOT / "docs" / "CONTRATOS.md"

# Repositorios de terceiros: pinados e compilaveis, mas nao sao codigo do time.
TERCEIROS = {"px4_msgs", "px4_ros2_interface", "behaviortree_cpp"}

FONTES = (".cpp", ".hpp", ".h", ".py")


# --------------------------------------------------------------------------- #
# Que arquivos olhar
# --------------------------------------------------------------------------- #

def repos_do_manifesto() -> list[str]:
    """Os repositorios do evtol.repos, menos os de terceiros.

    O manifesto e a fronteira entre "o codigo do time" e "o que por acaso esta
    em src/": itajuba, sae_2025 e cm204-evtol sao legado e nao entram.
    """
    manifesto = WS_ROOT / "evtol.repos"
    if not manifesto.is_file():
        return []
    try:
        import yaml
        repos = (yaml.safe_load(manifesto.read_text(encoding="utf-8")) or {}).get(
            "repositories", {})
    except Exception:
        return []
    return sorted(r for r in repos if r not in TERCEIROS)


def arquivos() -> list[tuple[str, Path]]:
    """(repo, caminho) de todo fonte de primeira mao."""
    saida: list[tuple[str, Path]] = []
    for repo in repos_do_manifesto():
        base = SRC / repo
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            if p.suffix in FONTES and ".git" not in p.parts and "build" not in p.parts:
                saida.append((repo, p))
    return saida


def rel(p: Path) -> str:
    return str(p.relative_to(WS_ROOT))


def ler(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


# --------------------------------------------------------------------------- #
# 1. Blocos-ancora
# --------------------------------------------------------------------------- #

ANCORA = re.compile(
    r"^[ \t]*(?://|#)[ \t]*>>>[ \t]*CONTRATO[ \t]+(?P<nome>[\w.\-]+)[ \t]*$"
    r"(?P<corpo>.*?)"
    r"^[ \t]*(?://|#)[ \t]*<<<[ \t]*CONTRATO[ \t]*$",
    re.S | re.M,
)


def ancoras() -> dict[str, list[tuple[str, str]]]:
    """{nome: [(arquivo, texto)]}, na ordem em que aparecem."""
    achadas: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for _repo, p in arquivos():
        texto = ler(p)
        if ">>> CONTRATO" not in texto:
            continue
        for m in ANCORA.finditer(texto):
            corpo = []
            for linha in m.group("corpo").splitlines():
                # Tira o marcador de comentario e UM espaco depois dele.
                limpa = re.sub(r"^[ \t]*(?://|#)[ \t]?", "", linha)
                corpo.append(limpa.rstrip())
            # Remove linhas vazias das pontas, preservando as do meio.
            while corpo and not corpo[0]:
                corpo.pop(0)
            while corpo and not corpo[-1]:
                corpo.pop()
            achadas[m.group("nome")].append((rel(p), "\n".join(corpo)))
    return achadas


# --------------------------------------------------------------------------- #
# 2. Topicos
# --------------------------------------------------------------------------- #

PUB_CPP = re.compile(r'create_publisher<[^>]*>\(\s*"([^"]+)"')
SUB_CPP = re.compile(r'create_subscription<[^>]*>\(\s*"([^"]+)"')
PUB_PY = re.compile(r'create_publisher\(\s*[\w.]+\s*,\s*[\'"]([^\'"]+)[\'"]')
SUB_PY = re.compile(r'create_subscription\(\s*[\w.]+\s*,\s*[\'"]([^\'"]+)[\'"]')


def topicos() -> dict[str, dict[str, set[str]]]:
    """{repo: {"pub": {...}, "sub": {...}}}"""
    saida: dict[str, dict[str, set[str]]] = defaultdict(
        lambda: {"pub": set(), "sub": set()})
    for repo, p in arquivos():
        texto = ler(p)
        for rx, chave in ((PUB_CPP, "pub"), (PUB_PY, "pub"),
                          (SUB_CPP, "sub"), (SUB_PY, "sub")):
            for nome in rx.findall(texto):
                # Ignora o que e claramente um parametro, e nao um topico.
                if nome and not nome.startswith("~"):
                    saida[repo][chave].add(nome)
    return saida


# --------------------------------------------------------------------------- #
# 3. Frequencias
# --------------------------------------------------------------------------- #

TIMER_CPP = re.compile(r"create_wall_timer\(\s*std::chrono::(\w+)\(([\d.]+)\)")
TIMER_PY = re.compile(r"create_timer\(\s*([\d.]+)")

EM_SEGUNDOS = {"seconds": 1.0, "milliseconds": 1e-3, "microseconds": 1e-6,
               "nanoseconds": 1e-9}


def frequencias() -> list[tuple[str, str, str]]:
    """[(arquivo, periodo, hz)]"""
    saida = []
    for _repo, p in arquivos():
        texto = ler(p)
        for unidade, valor in TIMER_CPP.findall(texto):
            fator = EM_SEGUNDOS.get(unidade)
            if not fator:
                continue
            s = float(valor) * fator
            if s > 0:
                saida.append((rel(p), f"{float(valor):g} {unidade}", f"{1/s:.4g} Hz"))
        for valor in TIMER_PY.findall(texto):
            s = float(valor)
            if s > 0:
                saida.append((rel(p), f"{s:g} s", f"{1/s:.4g} Hz"))
    return sorted(set(saida))


# --------------------------------------------------------------------------- #
# 4. Onde se comanda movimento  --  a tabela do "onde eu mexo"
# --------------------------------------------------------------------------- #

COMANDOS = re.compile(
    r"\b(setLocalPosition|setLocalVelocity|setMixedSetpoint|setLocalPositionSync"
    r"|move_local_by_speed|move_local_by_vel_as_position|move_local_constant_step"
    r"|irPara|land|arm|disarm)\s*\(")

# Uma definicao de funcao/metodo em C++, aproximada: o suficiente para dizer
# "dentro de qual funcao esta esta linha". Nao e um parser, e nao precisa ser.
#
# Casa tanto a assinatura que cabe numa linha quanto a que quebra em varias --
# esta ultima e comum aqui, e a primeira versao nao a pegava: o resultado era
# `MotionPolicy::irPara` sendo atribuido a `normalizarAngulo`, a funcao livre
# logo acima. Uma tabela de "onde eu mexo" que aponta para a funcao errada e
# pior do que nenhuma.
DEF_CPP = re.compile(
    r"^[ \t]*(?:[\w:<>,&*~\s]+?\s+)?(?:(\w+)::)?([A-Za-z_]\w*)\s*\("
    r"(?:[^;{]*\)\s*(?:const\s*)?(?:override\s*)?(?:noexcept\s*)?\{?)?\s*$")
DEF_PY = re.compile(r"^[ \t]*def\s+(\w+)\s*\(")

RUIDO = {"if", "for", "while", "switch", "catch", "return", "else", "do",
         "sizeof", "static_cast", "reinterpret_cast", "dynamic_cast"}

# Um TIPO logo antes do nome quer dizer DECLARACAO, e nao chamada. Sem isto, o
# `void move_local_by_speed(...);` do movement.hpp entrava na tabela como se
# fosse um ponto que comanda o drone -- e o header so anuncia a funcao.
TIPO_ANTES = re.compile(
    r"\b(?:void|bool|float|double|int|unsigned|char|auto|inline|static|virtual"
    r"|std::[\w:<>,\s]+|Eigen::[\w:<>,\s]+|[A-Z]\w*)\s*[&*]?\s*$")


def e_chamada(linha: str, nome: str) -> bool:
    """A ocorrencia de `nome` nesta linha e uma chamada, e nao uma declaracao?"""
    for m in re.finditer(r"\b" + re.escape(nome) + r"\s*\(", linha):
        antes = linha[:m.start()]
        # Chamada em objeto: nao ha como ser declaracao.
        if antes.rstrip().endswith(("->", ".", "::")):
            return True
        if not TIPO_ANTES.search(antes):
            return True
    return False


def funcao_de(linhas: list[str], i: int, py: bool) -> str:
    """A funcao que contem a linha i, olhando para tras."""
    if py:
        for j in range(i, max(-1, i - 200), -1):
            m = DEF_PY.match(linhas[j])
            if m and m.group(1) not in RUIDO:
                return m.group(1)
        return "?"

    for j in range(i, max(-1, i - 200), -1):
        m = DEF_CPP.match(linhas[j])
        if not m:
            continue
        classe, nome = m.group(1), m.group(2)
        if nome in RUIDO:
            continue
        return f"{classe}::{nome}" if classe else nome
    return "?"


def onde_se_comanda_movimento() -> list[tuple[str, str, int, str]]:
    """[(repo, arquivo, linha, funcao -> comandos)]"""
    saida = []
    for repo, p in arquivos():
        # O proprio drone_lib DEFINE esses metodos; listar as definicoes junto
        # com os usos faria a tabela dizer que o Drone.cpp "comanda movimento"
        # em trinta lugares, quando o que ele faz e implementa-los.
        if repo == "drone_lib" and p.name in ("Drone.cpp", "Drone.hpp"):
            continue
        texto = ler(p)
        linhas = texto.splitlines()
        py = p.suffix == ".py"
        for i, linha in enumerate(linhas):
            if linha.lstrip().startswith(("//", "#", "*")):
                continue
            nomes = sorted({n for n in set(COMANDOS.findall(linha))
                            if e_chamada(linha, n)})
            if not nomes:
                continue
            saida.append((repo, rel(p), i + 1, f"{funcao_de(linhas, i, py)}() -> "
                                                + ", ".join(nomes)))
    return saida


# --------------------------------------------------------------------------- #
# 5. Comandos do PX4
# --------------------------------------------------------------------------- #

VEHICLE_CMD = re.compile(r"VehicleCommand::(VEHICLE_CMD_\w+)")


def comandos_px4() -> list[tuple[str, str]]:
    saida = set()
    for _repo, p in arquivos():
        for linha in ler(p).splitlines():
            if linha.lstrip().startswith(("//", "#")):
                continue
            for cmd in VEHICLE_CMD.findall(linha):
                saida.add((cmd, rel(p)))
    return sorted(saida)


# --------------------------------------------------------------------------- #
# 6. Parametros: o diff entre simulacao e voo
# --------------------------------------------------------------------------- #

def parametros() -> list[tuple[str, list[tuple[str, str, str]]]]:
    """[(pacote, [(chave, valor_sim, valor_voo)])] -- so o que DIFERE."""
    try:
        import yaml
    except ImportError:
        return []

    saida = []
    for repo in repos_do_manifesto():
        base = SRC / repo
        if not base.is_dir():
            continue
        for cfg in sorted(base.rglob("config/simulation.yaml")):
            voo = cfg.with_name("flight.yaml")
            if not voo.is_file():
                continue
            try:
                a = yaml.safe_load(cfg.read_text(encoding="utf-8")) or {}
                b = yaml.safe_load(voo.read_text(encoding="utf-8")) or {}
            except Exception:
                continue

            def achatar(d, prefixo=""):
                fora = {}
                for k, v in (d or {}).items():
                    if k == "ros__parameters" and isinstance(v, dict):
                        fora.update(achatar(v, prefixo))
                    elif isinstance(v, dict):
                        fora.update(achatar(v, f"{prefixo}{k}."))
                    else:
                        fora[f"{prefixo}{k}"] = v
                return fora

            pa, pb = achatar(a), achatar(b)
            difs = []
            for k in sorted(set(pa) | set(pb)):
                va, vb = pa.get(k, "—"), pb.get(k, "—")
                if va != vb:
                    difs.append((k, str(va), str(vb)))
            if difs:
                saida.append((cfg.parent.parent.name, difs))
    return saida


# --------------------------------------------------------------------------- #
# 7. Camera e ROI
# --------------------------------------------------------------------------- #

TAMANHOS = re.compile(
    r"\b(capture_width|capture_height|frame_width|frame_height|image_width"
    r"|image_height|resize_width|published_size|camera_width|camera_height"
    r"|roi_width|roi_height|roi_x|roi_y|roi_margin|output_width|output_height"
    r"|camera_fx|camera_fy|camera_cx|camera_cy|camera_hfov|camera_yaw)\b")


def camera_e_roi() -> list[tuple[str, int, str]]:
    saida = []
    for _repo, p in arquivos():
        for i, linha in enumerate(ler(p).splitlines()):
            se = linha.strip()
            if se.startswith(("//", "#", "*")) or not TAMANHOS.search(linha):
                continue
            # So as linhas que atribuem ou declaram um valor.
            if not re.search(r"[=:]", linha):
                continue
            saida.append((rel(p), i + 1, se[:110]))
    return saida


# --------------------------------------------------------------------------- #
# Montagem do documento
# --------------------------------------------------------------------------- #

CABECALHO = """<!--
    ARQUIVO GERADO. Nao edite a mao.

        python3 scripts/contratos.py

    O que esta aqui foi extraido do codigo. Para mudar uma linha deste
    documento, mude o codigo -- ou o bloco-ancora dentro dele -- e regenere.
    O CI reprova quando os dois discordam.
-->

# Contratos do workspace eVTOL

O que o sistema assume, tirado do proprio codigo.

**Este documento nao e a fonte da verdade: o codigo e.** Aqui e a vista dele,
reunida num lugar so para a hora em que se esta depurando um voo e nao da para
abrir sessenta arquivos. Se algo aqui parecer errado, o certo esta no arquivo
citado ao lado -- e entao este documento esta desatualizado, o que o
`--check` do CI existe para impedir.

Para acrescentar uma explicacao a este documento, escreva um bloco-ancora no
proprio codigo, onde ela pertence:

```cpp
// >>> CONTRATO frames.exemplo
// A explicacao, que continua morando junto do codigo que ela descreve.
// <<< CONTRATO
```

"""


def secao(titulo: str, corpo: str) -> str:
    return f"\n## {titulo}\n\n{corpo.rstrip()}\n"


def gerar() -> str:
    partes = [CABECALHO]

    # --- Ancoras -------------------------------------------------------------
    anc = ancoras()
    if anc:
        corpo = []
        for nome in sorted(anc):
            for arquivo, texto in anc[nome]:
                corpo.append(f"### `{nome}`\n")
                corpo.append(f"Fonte: [{arquivo}]({arquivo})\n")
                corpo.append("```")
                corpo.append(texto)
                corpo.append("```\n")
        partes.append(secao("Convencoes declaradas no codigo", "\n".join(corpo)))
    else:
        partes.append(secao(
            "Convencoes declaradas no codigo",
            "_Nenhum bloco-ancora encontrado._ Ver o cabecalho sobre como criar um."))

    # --- Movimento -----------------------------------------------------------
    mov = onde_se_comanda_movimento()
    corpo = [
        "Onde nasce um comando de movimento. **Esta e a tabela para consultar",
        "quando a pergunta for \"onde eu mexo para mudar como o drone anda\".**",
        "",
        "Os estados do `stdstates` passam pela `drone::MotionPolicy`, que se",
        "escolhe com `motion_policy` no YAML da missao (`holonomica` ou `axial`).",
        "As linhas abaixo que NAO citam `irPara` comandam o drone direto, e sao",
        "as que uma mudanca de regra de movimento teria de tocar uma a uma.",
        "",
        "| repositorio | arquivo:linha | funcao |",
        "|---|---|---|",
    ]
    for repo, arquivo, linha, o_que in mov:
        corpo.append(f"| {repo} | [{arquivo}:{linha}]({arquivo}#L{linha}) | {o_que} |")
    corpo.append("")
    corpo.append(f"Total: **{len(mov)}** pontos.")
    partes.append(secao("Onde se comanda movimento", "\n".join(corpo)))

    # --- Topicos -------------------------------------------------------------
    tops = topicos()
    corpo = []
    for repo in sorted(tops):
        pub = sorted(tops[repo]["pub"])
        sub = sorted(tops[repo]["sub"])
        if not pub and not sub:
            continue
        corpo.append(f"### {repo}\n")
        if pub:
            corpo.append("publica: " + ", ".join(f"`{t}`" for t in pub) + "\n")
        if sub:
            corpo.append("assina: " + ", ".join(f"`{t}`" for t in sub) + "\n")
    partes.append(secao("Topicos", "\n".join(corpo)))

    # --- Frequencias ---------------------------------------------------------
    corpo = ["| arquivo | periodo | taxa |", "|---|---|---|"]
    for arquivo, periodo, hz in frequencias():
        corpo.append(f"| [{arquivo}]({arquivo}) | {periodo} | {hz} |")
    partes.append(secao("Frequencias", "\n".join(corpo)))

    # --- PX4 -----------------------------------------------------------------
    corpo = ["| comando | onde |", "|---|---|"]
    for cmd, arquivo in comandos_px4():
        corpo.append(f"| `{cmd}` | [{arquivo}]({arquivo}) |")
    partes.append(secao("Comandos do PX4 em uso", "\n".join(corpo)))

    # --- Parametros ----------------------------------------------------------
    corpo = [
        "So o que **difere** entre `simulation.yaml` e `flight.yaml`. E esse",
        "diff que interessa antes de voar: o que e igual nos dois ja foi",
        "exercitado na simulacao.",
        "",
    ]
    for pacote, difs in parametros():
        corpo.append(f"### {pacote}\n")
        corpo.append("| parametro | simulacao | voo |")
        corpo.append("|---|---|---|")
        for k, va, vb in difs:
            corpo.append(f"| `{k}` | {va} | {vb} |")
        corpo.append("")
    partes.append(secao("Parametros: simulacao x voo", "\n".join(corpo)))

    # --- Camera --------------------------------------------------------------
    corpo = ["| arquivo:linha | declaracao |", "|---|---|"]
    for arquivo, linha, texto in camera_e_roi():
        escapado = texto.replace("|", "\\|").replace("`", "'")
        corpo.append(f"| [{arquivo}:{linha}]({arquivo}#L{linha}) | `{escapado}` |")
    partes.append(secao("Camera, intrinsecos e ROI", "\n".join(corpo)))

    return "".join(partes)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="so verifica; sai 1 se estiver desatualizado")
    args = ap.parse_args()

    if not SRC.is_dir():
        print(f"ERRO: {SRC} nao existe. Rode o vcs import antes.", file=sys.stderr)
        return 1

    novo = gerar()
    atual = SAIDA.read_text(encoding="utf-8") if SAIDA.is_file() else None

    if atual == novo:
        print("docs/CONTRATOS.md esta em dia.")
        return 0

    if args.check:
        print("docs/CONTRATOS.md DESATUALIZADO em relacao ao codigo.", file=sys.stderr)
        print("  rode: python3 scripts/contratos.py", file=sys.stderr)
        return 1

    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(novo, encoding="utf-8")
    print(f"docs/CONTRATOS.md gerado ({len(novo.splitlines())} linhas).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
