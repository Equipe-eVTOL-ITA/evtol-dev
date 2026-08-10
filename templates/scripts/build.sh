#!/usr/bin/env bash
# =============================================================================
# Template: build.sh — compila os pacotes desta competição.
# =============================================================================
#
#   ./scripts/build.sh <alvo>
#
# Alvos que já vêm prontos:
#   deps   — só as bibliotecas compartilhadas (rápido, use depois de um
#            `vcs import` ou quando alguém bumpar um pin)
#   all    — tudo o que estiver em src/
#
# Copie para o scripts/ da sua competição e acrescente um alvo por missão.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# <ws>/src/<competicao>/scripts/  ->  <ws>
ws_root="$(cd "$script_dir/../../.." && pwd)"
comp_dir="$(cd "$script_dir/.." && pwd)"

# Carrega a distro do perfil desta máquina. Nunca escreva
# `source /opt/ros/humble/setup.bash` aqui: voamos com Humble na Jetson e
# Jazzy na Raspberry, e o mesmo script serve aos dois.
source "$ws_root/scripts/ros_env.sh"

cd "$ws_root"

BUILD_TYPE=RelWithDebInfo
# --executor sequential evita picos de RAM (veja docs/SETUP.md, seção de swap).
COMMON=(--symlink-install --executor sequential
        --cmake-args "-DCMAKE_BUILD_TYPE=$BUILD_TYPE" "-DCMAKE_EXPORT_COMPILE_COMMANDS=On")

usage() {
    echo "Uso: $0 <alvo>"
    echo "  deps   — só as bibliotecas compartilhadas"
    echo "  all    — tudo"
    echo "  <pkg>  — um pacote desta competição:"
    colcon list --names-only --base-paths "$comp_dir" 2>/dev/null | sed 's/^/           /'
}

case "${1:-}" in
    deps)
        colcon build "${COMMON[@]}" --packages-up-to stdstates
        ;;
    all)
        colcon build "${COMMON[@]}"
        ;;
    "" | -h | --help)
        usage; exit 1
        ;;
    *)
        # Aceita qualquer pacote desta competição, sem precisar listá-los aqui.
        if colcon list --names-only --base-paths "$comp_dir" 2>/dev/null | grep -qx "$1"; then
            colcon build "${COMMON[@]}" --packages-up-to "$1"
        else
            echo "Alvo desconhecido: '$1'" >&2; echo >&2; usage >&2; exit 1
        fi
        ;;
esac

echo
echo "Pronto. Em cada shell novo, a partir de $ws_root:"
echo "    source scripts/ros_env.sh"
