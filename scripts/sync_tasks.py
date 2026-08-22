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
    missoes      -> pacotes com launch/simulation.launch.py
    solo         -> pacotes com um launch de estacao de solo
    alvos        -> all, deps, changed + TODO pacote colcon do workspace

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

# Repositorios do manifesto que sao de TERCEIROS. Estao pinados e sao
# compilaveis, mas nao sao codigo do time: o px4_ros2_interface sozinho traz
# catorze pacotes `example_*` que ninguem daqui compila de proposito.
TERCEIROS = {"px4_msgs", "px4_ros2_interface", "behaviortree_cpp"}


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


def pacotes_do_workspace() -> list[str]:
    """Todo pacote colcon de src/, sem qualificar por competicao.

    POR QUE A LISTA DE BUILD DEIXOU DE SER `competicao:alvo`

    Ela era qualificada como as outras, e isso escondia dois problemas.

    Pacote que nao pertence a competicao nenhuma nao aparecia: camera_publisher,
    cv_nodes, drone_lib, stdstates. Justamente os que mais se mexe, e os unicos
    que quebram todas as missoes de uma vez -- nao havia como compila-los pela
    task.

    E `all` fazia a mesma coisa nos quatro prefixos, porque os build.sh das
    competicoes rodam `colcon build` sobre o src/ inteiro. `cbr2026:all` e
    `sae2026:all` eram o mesmo comando com um rotulo diferente.

    O `scripts/build.sh` da raiz aceita nome de pacote e pronto, entao a lista
    aqui e plana. A competicao nao entra porque nunca fez diferenca.
    """
    try:
        r = subprocess.run(
            ["colcon", "list", "--names-only", "--base-paths", str(SRC)],
            capture_output=True, text=True, timeout=120, cwd=WS_ROOT,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0:
        return []
    return sorted({p for p in r.stdout.split() if p})


def pacotes_dos_repos_do_manifesto() -> set[str]:
    """Pacotes que vem dos repositorios listados no evtol.repos.

    O evtol.repos e a fronteira entre "o codigo do time" e "o que por acaso
    esta em src/". Usa-la aqui e o mesmo criterio que o scripts/build.sh usa
    no --changed. Os repositorios de TERCEIROS ficam de fora: estao no
    manifesto, mas nao sao o que alguem procura na lista de compilar.
    """
    manifesto = WS_ROOT / "evtol.repos"
    if not manifesto.is_file():
        return set()
    try:
        import yaml
        repos = (yaml.safe_load(manifesto.read_text(encoding="utf-8")) or {}).get(
            "repositories", {})
    except Exception:
        return set()

    nomes: set[str] = set()
    for repo in repos:
        if repo in TERCEIROS:
            continue
        nomes.update(pacotes_de_base(SRC / repo))
    return nomes


def pacotes_de_base(base: Path) -> list[str]:
    """Pacotes colcon sob um diretorio."""
    if not base.is_dir():
        return []
    try:
        r = subprocess.run(
            ["colcon", "list", "--names-only", "--base-paths", str(base)],
            capture_output=True, text=True, timeout=60, cwd=WS_ROOT,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    return sorted(p for p in r.stdout.split() if p) if r.returncode == 0 else []


# Os nomes de launch de solo em uso, do mais atual para o mais antigo. A mesma
# lista esta em scripts/ground_station.sh, que e quem de fato os executa.
LAUNCHES_DE_SOLO = ("ground.launch.py", "ground_station.launch.py",
                    "groundstation.launch.py")


def pacotes_de_solo(comp: str) -> list[str]:
    """Pacotes da competicao que tem uma estacao de solo para subir.

    A task "voo: ground station" oferecia a mesma lista das missoes -- dez
    opcoes, e NENHUMA delas com um launch de solo. As dez falhavam igual, com
    um "launch file not found" que parecia problema de compilacao.

    Mesmo criterio das missoes: so entra na lista o que da para lancar.
    """
    base = SRC / comp
    if not base.is_dir():
        return []
    return sorted(
        d.name for d in base.iterdir()
        if any((d / "launch" / nome).is_file() for nome in LAUNCHES_DE_SOLO)
    )


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
    missoes_q: list[str] = []
    solo_q: list[str] = []
    for c in comps:
        mundos_q += [f"{c}:{m}" for m in mundos(c)]
        missoes_q += [f"{c}:{m}" for m in missoes(c)]
        solo_q += pacotes_de_solo(c)
    mundos_q = sorted(set(mundos_q))
    missoes_q = sorted(set(missoes_q))
    # Nao qualificado: ha um input so, entao nao existe combinacao invalida a
    # evitar -- que era a unica razao de qualificar os outros.
    solo_q = sorted(set(solo_q))

    # Os tres primeiros sao alvos do scripts/build.sh, nao pacotes.
    #
    # Depois deles vem os pacotes DO MANIFESTO, e so entao o resto.
    #
    # A ordem importa porque a lista tem 60 itens e o VS Code a mostra inteira:
    # src/ guarda tambem trabalho legado (itajuba_*, sae_*, cbr2025_fase4) e os
    # catorze `example_*` que vem dentro do px4_ros2_interface. Deixa-los de
    # fora seria mentir -- sao compilaveis, e um dia alguem vai precisar de um.
    # Mas eles nao podem ficar na frente do que o time compila todo dia.
    todos = pacotes_do_workspace()
    do_manifesto = pacotes_dos_repos_do_manifesto()
    alvos_q = (["all", "deps", "changed"]
               + [p for p in todos if p in do_manifesto]
               + [p for p in todos if p not in do_manifesto])

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
        pick("alvoBuild", "O que compilar (pacote, ou all/deps/changed)",
             alvos_q, "changed"),
        # Qualificado tambem, para dizer de que competicao a missao e. A task
        # descarta a parte antes do ":" antes de chamar o ros2 launch.
        pick("pacoteMissao", "Missão (competição:missão)", missoes_q,
             "sae2026:mission_1"),
        pick("pacoteGround", "Estação de solo (pacote)", solo_q, "fase3"),
        # Texto livre, e nao lista.
        #
        # A lista suspensa cobre o que existe AGORA. Um pacote criado hoje so
        # aparece nela depois de rodar este script, e quem acabou de criar a
        # missao e justamente quem precisa compila-la. Este input aceita
        # qualquer nome -- e varios, separados por espaco -- sem esperar
        # sincronizacao nenhuma. O build.sh valida e sugere se errar.
        {
            "id": "pacotesDigitados",
            "description": "Pacote(s) a compilar, separados por espaço",
            "type": "promptString",
            "default": "",
        },
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
        # promptString e texto livre: nao tem 'options'.
        opcoes = ", ".join(i["options"]) if "options" in i else "(texto livre)"
        print(f"  {i['id']:16} {opcoes}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
