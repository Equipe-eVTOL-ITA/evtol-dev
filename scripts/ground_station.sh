#!/usr/bin/env bash
# =============================================================================
# ground_station.sh — sobe a estação de solo de uma missão.
# =============================================================================
#
#   ./scripts/ground_station.sh fase3
#   ./scripts/ground_station.sh fase3 -- <argumentos extras do ros2 launch>
#
# Procura entre os nomes em uso em vez de adivinhar um: a versão anterior
# chamava sempre `ground_station.launch.py`, que nenhum pacote do manifesto tem
# -- o que existe é `ground.launch.py`, na fase3.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

# Nunca `source /opt/ros/humble/...` aqui: quebra as máquinas com Jazzy.
# shellcheck source=scripts/ros_env.sh
source "$ws_root/scripts/ros_env.sh"

pacote="${1:-}"
if [[ -z "$pacote" ]]; then
    echo "uso: $0 <pacote_da_missao> [-- <args do ros2 launch>]" >&2
    echo "  ex.: $0 fase3" >&2
    exit 1
fi
shift
[[ "${1:-}" == "--" ]] && shift

share="$(ros2 pkg prefix "$pacote" 2>/dev/null)/share/$pacote" || true
if [[ ! -d "$share" ]]; then
    echo "ground_station.sh: o pacote '$pacote' não está instalado." >&2
    echo "                   Compile antes:  ./scripts/build.sh $pacote" >&2
    exit 1
fi

# Os nomes em uso, do mais atual para o mais antigo.
CANDIDATOS=(ground.launch.py ground_station.launch.py groundstation.launch.py)

launch=""
for c in "${CANDIDATOS[@]}"; do
    if [[ -f "$share/launch/$c" ]]; then
        launch="$c"
        break
    fi
done

if [[ -z "$launch" ]]; then
    echo "ground_station.sh: '$pacote' não tem launch de solo." >&2
    echo "                   Procurei por: ${CANDIDATOS[*]}" >&2
    echo >&2
    echo "                   O que existe em $share/launch:" >&2
    if compgen -G "$share/launch/*" >/dev/null; then
        find "$share/launch" -maxdepth 1 -name '*.launch.py' -printf '                       %f\n' >&2
    else
        echo "                       (nenhum launch)" >&2
    fi
    exit 1
fi

echo "Estação de solo — $pacote ($launch)"
exec ros2 launch "$pacote" "$launch" "$@"
