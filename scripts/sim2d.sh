#!/usr/bin/env bash
# =============================================================================
# sim2d.sh — sobe o simulador 2D já configurado pela própria fase.
# =============================================================================
#
#   ./scripts/sim2d.sh <pacote_da_fase> [--com-missao] [-- <extras do sim2d>]
#
#   ./scripts/sim2d.sh fase4
#   ./scripts/sim2d.sh fase4 --com-missao
#   ./scripts/sim2d.sh fase4 -- -p deriva_por_metro:=0.02 -p grafico:=false
#
# POR QUE O --com-missao EXISTE
#
# Rodar uma fase no simulador 2D são duas coisas: o simulador e a missão. Como
# eram duas tasks do VSCode, e as duas precisavam saber QUAL fase, o VSCode
# perguntava a mesma coisa duas vezes -- ele resolve os inputs por task, e não
# por execução. Aqui a resposta é uma só, e a ordem entre as duas (o simulador
# primeiro) deixa de depender de um `sleep` escrito na task.
#
# POR QUE ELE LÊ O CONFIG DA FASE
#
# O simulador precisa saber o mapa e onde o drone decola. A missão precisa
# saber exatamente o mesmo, e já sabe: está no `config/simulation.yaml` dela.
#
# Digitar esses números na linha de comando cria uma segunda cópia deles, e a
# divergência não dá erro nenhum — dá um drone que começa a missão acreditando
# estar noutro lugar. É a mesma razão pela qual o mapa é um arquivo só, lido
# pela missão e pelo simulador.
#
# Aqui o simulador é derivado do config, e não pode discordar dele.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

fase="${1:-}"
if [[ -z "$fase" ]]; then
    echo "uso: $0 <pacote_da_fase> [--com-missao] [-- <parametros extras>]" >&2
    echo "  ex.: $0 fase4" >&2
    exit 1
fi
shift

com_missao=0
while [[ $# -gt 0 && "${1:-}" != "--" ]]; do
    case "$1" in
        --com-missao) com_missao=1; shift ;;
        *) echo "sim2d.sh: argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done
[[ "${1:-}" == "--" ]] && shift

# shellcheck disable=SC1091
source "$ws_root/scripts/ros_env.sh"

share="$(ros2 pkg prefix "$fase" 2>/dev/null)/share/$fase"
config="$share/config/simulation.yaml"

if [[ ! -f "$config" ]]; then
    echo "sim2d.sh: '$config' nao existe." >&2
    echo "          A fase foi compilada? Rode a task 'build'." >&2
    exit 1
fi

# Os parametros saem do YAML, e nao daqui. `mapa` pode vir como nome simples
# (resolvido no share da propria fase) ou como caminho.
leitura="$(python3 - "$config" "$share" <<'PY'
import os, sys, yaml
cfg, share = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(cfg))
p = next(iter(d.values()))["ros__parameters"]

mapa = p.get("mapa")
if not mapa:
    sys.exit("o config da fase nao declara 'mapa'")
if not os.path.isabs(mapa):
    mapa = os.path.join(share, "maps", mapa)

print(f"MAPA={mapa}")
for chave in ("inicio_x", "inicio_y", "inicio_yaw"):
    if chave in p:
        print(f"{chave.upper()}={p[chave]}")
PY
)"
eval "$leitura"

if [[ ! -f "$MAPA" ]]; then
    echo "sim2d.sh: o mapa '$MAPA' nao existe." >&2
    exit 1
fi

echo "Simulador 2D — fase '$fase'"
echo "  mapa:   $MAPA"
echo "  inicio: (${INICIO_X:-0}, ${INICIO_Y:-0}) proa ${INICIO_YAW:-0} rad"
echo "  (os tres vem do config da fase, e nao desta linha de comando)"
echo

if (( com_missao )); then
    # A missão entra em SEGUNDO plano e o simulador fica em primeiro.
    #
    # Nesta ordem porque é o simulador que tem o gráfico: quem está olhando
    # quer o Ctrl+C dele. O trap garante que a missão não sobreviva ao
    # simulador -- um nó de missão órfão continua publicando setpoints, e a
    # rodada seguinte herda um segundo publicador sem ninguém perceber.
    (
        # 3 s: o mesmo tempo que a task usava, e pela mesma razão -- a missão
        # lê a odometria do simulador no primeiro tick.
        sleep 3
        exec ros2 run "$fase" "$fase" --ros-args \
            --params-file "$config" \
            -p groot2_port:=0.0
    ) &
    missao_pid=$!
    trap 'kill -INT "$missao_pid" 2>/dev/null || true' EXIT INT TERM
    echo "  missão '$fase' sobe em 3 s (pid $missao_pid)"
    echo
fi

# Sem `exec` quando há missão junto.
#
# `exec` substitui este shell pelo simulador -- e com ele vão embora os traps.
# A missão em segundo plano sobreviveria ao Ctrl+C, continuaria publicando
# setpoints, e a rodada seguinte subiria com dois publicadores no mesmo tópico.
# O trap só serve se houver um shell vivo para executá-lo.
if (( com_missao )); then
    ros2 run sim2d sim2d --ros-args \
        -p mapa:="$MAPA" \
        -p inicio_x:="${INICIO_X:-0.0}" \
        -p inicio_y:="${INICIO_Y:-0.0}" \
        -p inicio_yaw:="${INICIO_YAW:-0.0}" \
        "$@"
    exit $?
fi

exec ros2 run sim2d sim2d --ros-args \
    -p mapa:="$MAPA" \
    -p inicio_x:="${INICIO_X:-0.0}" \
    -p inicio_y:="${INICIO_Y:-0.0}" \
    -p inicio_yaw:="${INICIO_YAW:-0.0}" \
    "$@"
