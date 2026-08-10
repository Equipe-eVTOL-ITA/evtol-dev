#!/usr/bin/env bash
# =============================================================================
# Template: agent.sh — sobe o Micro XRCE-DDS Agent (ponte PX4 <-> ROS 2).
# =============================================================================
#
#   ./scripts/agent.sh          # simulação (UDP)
#
# Normalmente NÃO precisa de customização. Em voo real, com o Pixhawk ligado
# por serial, troque a última linha por algo como:
#     MicroXRCEAgent serial --dev /dev/ttyTHS1 -b 921600
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/../../.." && pwd)"

source "$ws_root/scripts/ros_env.sh"

export PATH="$PATH:/usr/local/bin"

if ! command -v MicroXRCEAgent >/dev/null 2>&1; then
    echo "ERRO: MicroXRCEAgent não encontrado." >&2
    echo "      Veja docs/SETUP.md seção 5. O doctor.sh também confere isso." >&2
    exit 1
fi

echo "Micro XRCE-DDS Agent — simulação (UDP porta 8888)"
exec MicroXRCEAgent udp4 -p 8888
