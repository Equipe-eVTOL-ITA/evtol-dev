#!/usr/bin/env bash
# =============================================================================
# doctor.sh — verifica se esta máquina bate com o perfil de ambiente declarado.
# =============================================================================
#
#   ./doctor.sh                          # usa o perfil de .evtol-profile
#   ./doctor.sh --profile desktop-humble # força um perfil
#   ./doctor.sh --list                   # lista os perfis disponíveis
#
# Sai com código 0 se o ambiente confere, 1 se não. É por isso que ele pode ser
# usado dentro do setup.sh e do CI como portão.
#
# Por que isso existe: o evtol.repos garante que todo mundo tem o mesmo CÓDIGO.
# Ele não tem como garantir que todo mundo tem o mesmo AMBIENTE — mesma distro
# do ROS, mesma versão do Gazebo, mesma variante do bridge, mesmo OpenCV. Foi
# sempre aí que os bugs caros do time nasceram, porque essa classe de erro não
# gera mensagem de erro: gera comportamento estranho sem causa aparente.
# =============================================================================

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERRO: python3 não encontrado no PATH." >&2
    exit 1
fi

exec python3 "$script_dir/env/doctor.py" "$@"
