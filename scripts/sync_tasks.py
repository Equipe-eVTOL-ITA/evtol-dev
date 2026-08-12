#!/usr/bin/env python3
"""Regenera as listas suspensas das tasks do VS Code a partir do que existe.

Por que isso existe
-------------------
O VS Code so aceita lista FIXA nos campos de entrada de uma task -- escrita a
mao dentro do `.vscode/tasks.json`. Lista escrita a mao envelhece: a versao
anterior deste arquivo oferecia apenas a competicao `sae2026` e a missao
`mission_1`, entao quem criasse a `cbr2026` com a `fase1` simplesmente nao a
encontrava nas tasks, e tinha que voltar para o terminal.

Este script resolve pelo outro lado: em vez de manter a lista a mao, ele a
DERIVA do workspace.

    competicoes  -> diretorios em src/ que tem scripts/simulate.sh
    mundos       -> os rotulos do bloco `case` de cada simulate.sh
    missoes      -> pacotes colcon de cada competicao
    alvos        -> all, deps + os pacotes de cada competicao

Rode depois de criar uma competicao ou uma missao. O `setup.sh` ja roda no
final, e o `templates/new_mission.sh` deve roda-lo tambem.

Uso
---
    python3 scripts/sync_tasks.py           # atualiza .vscode/tasks.json
    python3 scripts/sync_tasks.py --check   # so diz se esta desatualizado

E idempotente: rodar duas vezes nao muda nada na segunda.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

WS_ROOT = Path(__file__).resolve().parent.parent
SRC = WS_ROOT / "src"
TASKS = WS_ROOT / ".vscode" / "tasks.json"

# Diretorios em src/ que nao sao competicoes do time.
IGNORAR = {"px4_msgs", "px4_ros2_interface", "evtol-dev"}


def competicoes() -> list[str]:
    """Diretorios em src/ com scripts/simulate.sh -- e a definicao de competicao."""
    if not SRC.is_dir():
        return []
    return sorted(
        d.name
        for d in SRC.iterdir()
        if d.is_dir() and d.name not in IGNORAR and (d / "scripts" / "simulate.sh").is_file()
    )


def mundos(comp: str) -> list[str]:
    """Rotulos do bloco `case` do simulate.sh da competicao.

    Pega `fase1)` e `sae1|sae2)`, ignora o `*)` e o que estiver comentado --
    e por isso que o exemplo comentado do template nao vira uma opcao falsa.
    """
    sim = SRC / comp / "scripts" / "simulate.sh"
    try:
        texto = sim.read_text(encoding="utf-8")
    except OSError:
        return []

    bloco = re.search(r"^case\s+.*?\bin\s*$(.*?)^esac", texto, re.S | re.M)
    if not bloco:
        return []

    achados: list[str] = []
    for linha in bloco.group(1).splitlines():
        if linha.lstrip().startswith("#"):
            continue
        m = re.match(r"\s*([A-Za-z0-9_|\- ]+)\)\s*$", linha)
        if m:
            achados.extend(p.strip() for p in m.group(1).split("|") if p.strip())
    return sorted(set(achados))


def pacotes(comp: str) -> list[str]:
    """Pacotes colcon da competicao."""
    try:
        r = subprocess.run(
            ["colcon", "list", "--names-only", "--base-paths", str(SRC / comp)],
            capture_output=True, text=True, timeout=60, cwd=WS_ROOT,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0:
        return []
    return sorted(p for p in r.stdout.split() if p)


def missoes(comp: str) -> list[str]:
    """Pacotes da competicao que sao MISSAO de verdade.

    O criterio e ter `launch/simulation.launch.py` -- que e exatamente o que a
    task "sim: rodar missao" executa. Sem esse filtro, a lista misturava
    pacotes de apoio (`audio_alert`) e pacotes de outros projetos que estao no
    src/ (`cbr2025_fase4`), e quem escolhesse um deles recebia um erro do
    `ros2 launch` sem entender por que aquilo estava na lista.

    Listar so o que da para lancar e melhor do que validar depois: a escolha
    errada deixa de existir.
    """
    base = SRC / comp
    if not base.is_dir():
        return []
    return sorted(
        d.name for d in base.iterdir()
        if (d / "launch" / "simulation.launch.py").is_file()
    )


def montar_inputs() -> list[dict]:
    """Monta os inputs do tasks.json a partir do que existe em src/.

    Opcoes de mundo e de alvo de build sao QUALIFICADAS: `competicao:valor`.

    O motivo e uma limitacao do VS Code -- um input nao consegue depender da
    resposta de outro. Com um input separado para a competicao, era possivel
    escolher `cbr2026` e depois receber `mission_1` na lista de alvos, que so
    existe no sae2026. A lista mentia.

    Qualificando, a pergunta da competicao deixa de existir: cada opcao ja
    carrega a competicao a que pertence, e nenhuma combinacao invalida pode
    ser montada. Uma pergunta a menos, e nenhuma resposta errada possivel.
    """
    comps = competicoes()

    mundos_q: list[str] = []
    alvos_q: list[str] = []
    missoes_q: list[str] = []
    for c in comps:
        mundos_q += [f"{c}:{m}" for m in mundos(c)]
        alvos_q += [f"{c}:all", f"{c}:deps"] + [f"{c}:{p}" for p in pacotes(c)]
        missoes_q += [f"{c}:{m}" for m in missoes(c)]
    mundos_q = sorted(set(mundos_q))
    alvos_q = sorted(set(alvos_q))
    missoes_q = sorted(set(missoes_q))

    def pick(id_, desc, opts, default=None):
        opts = opts or [""]
        return {
            "id": id_,
            "description": desc,
            "type": "pickString",
            "options": opts,
            "default": default if default in opts else opts[0],
        }

    return [
        # O default e so o valor pre-selecionado; qualquer opcao da lista serve.
        pick("mundo", "Mundo do Gazebo (competição:mundo)", mundos_q, "sae2026:sae1"),
        pick("alvoBuild", "O que compilar (competição:alvo)", alvos_q, "sae2026:all"),
        # Qualificado tambem, para dizer de que competicao a missao e. A task
        # descarta a parte antes do ":" antes de chamar o ros2 launch.
        pick("pacoteMissao", "Missão (competição:missão)", missoes_q,
             "sae2026:mission_1"),
    ]


def carregar(texto: str) -> dict:
    """Le JSONC (o tasks.json aceita comentarios)."""
    sem_linha = re.sub(r"^\s*//.*$", "", texto, flags=re.M)
    return json.loads(sem_linha)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="so verifica; sai 1 se estiver desatualizado")
    args = ap.parse_args()

    if not TASKS.is_file():
        print(f"ERRO: {TASKS} nao encontrado.", file=sys.stderr)
        return 1

    texto = TASKS.read_text(encoding="utf-8")
    try:
        dados = carregar(texto)
    except json.JSONDecodeError as e:
        print(f"ERRO: {TASKS} nao e JSON valido: {e}", file=sys.stderr)
        return 1

    novos = montar_inputs()
    if dados.get("inputs") == novos:
        print("Tasks do VS Code ja estao sincronizadas.")
        return 0

    if args.check:
        print("Tasks do VS Code DESATUALIZADAS.", file=sys.stderr)
        print("  rode: python3 scripts/sync_tasks.py", file=sys.stderr)
        return 1

    # Substitui so o bloco "inputs", preservando comentarios e formatacao do
    # resto do arquivo -- reescrever tudo apagaria a documentacao interna.
    bloco = json.dumps({"inputs": novos}, ensure_ascii=False, indent=4)
    bloco = bloco[bloco.index('"inputs"'):bloco.rindex("}")].rstrip().rstrip(",")
    # json.dumps ja indenta 4; o bloco vive dentro do objeto raiz, entao a
    # primeira linha precisa de 4 e as demais ja estao no nivel certo.
    linhas = bloco.splitlines()
    bloco = "\n".join(["    " + linhas[0]] + linhas[1:])

    novo_texto, n = re.subn(
        r'^    "inputs"\s*:\s*\[.*?^    \]',
        lambda _: bloco,
        texto,
        flags=re.S | re.M,
    )
    if n != 1:
        print("ERRO: nao consegui localizar o bloco 'inputs' para substituir.",
              file=sys.stderr)
        return 1

    TASKS.write_text(novo_texto, encoding="utf-8")

    print("Tasks do VS Code sincronizadas:")
    for i in novos:
        print(f"  {i['id']:14} {', '.join(i['options'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
