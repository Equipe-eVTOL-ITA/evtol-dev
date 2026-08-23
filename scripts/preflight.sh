#!/usr/bin/env bash
# =============================================================================
# preflight.sh — confere o sistema RODANDO contra o que o contrato promete.
# =============================================================================
#
#   ./scripts/preflight.sh fase1            confere o perfil de voo
#   ./scripts/preflight.sh fase1 --sim      confere o de simulacao
#
# Rode com a missao no ar, ANTES de armar.
#
# O docs/CONTRATOS.md e os testes garantem que o CODIGO e a DOCUMENTACAO
# concordam. Esta camada pega o caso em que os dois concordam e A MAQUINA faz
# outra coisa: topico sem publicador, QoS que nao casa, camera no default,
# intrinseco ainda placeholder. Nenhuma dessas falhas imprime erro.
#
# Sai com codigo 0 se tudo passou, e 1 se algo reprovou.
# =============================================================================
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=scripts/ros_env.sh
source "$ws_root/scripts/ros_env.sh"

pacote="${1:-}"
perfil="flight"
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sim|--simulacao) perfil="simulation"; shift ;;
        --voo|--flight)    perfil="flight"; shift ;;
        -h|--help)
            sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=\+$'; exit 0 ;;
        *) echo "preflight.sh: argumento desconhecido: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$pacote" ]]; then
    echo "uso: $0 <pacote_da_missao> [--sim]" >&2
    exit 2
fi

share="$(ros2 pkg prefix "$pacote" 2>/dev/null)/share/$pacote"
config="$share/config/$perfil.yaml"
if [[ ! -f "$config" ]]; then
    echo "preflight.sh: '$config' nao existe. A missao foi compilada?" >&2
    exit 2
fi

echo "Pre-voo — $pacote ($perfil)"
echo "perfil de ambiente: ${EVTOL_PROFILE:-?}"
echo

exec python3 "$ws_root/scripts/preflight.py" "$pacote" "$config"
