#!/usr/bin/env bash
# =============================================================================
# ros_env.sh — carrega o ambiente ROS correto para ESTA máquina.
# =============================================================================
#
#   source scripts/ros_env.sh
#
# Descobre a distro a partir do perfil registrado em .evtol-profile e carrega
# /opt/ros/<distro>/setup.bash e, se existir, install/setup.bash.
#
# Existe para que nenhum script, task do VSCode ou instrução de documentação
# escreva "humble" literalmente. O time voa com Jetson (Humble) e Raspberry Pi
# (Jazzy) ao mesmo tempo, e um "source /opt/ros/humble/setup.bash" copiado para
# a máquina errada é uma das formas mais baratas de perder uma tarde.
#
# Feito para ser SOURCED, não executado — por isso não usa `set -e` nem `exit`.
# =============================================================================

# shellcheck shell=bash

_evtol_ros_env() {
    local script_dir ws_root profile profile_file distro

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ws_root="$(cd "$script_dir/.." && pwd)"

    if [[ ! -f "$ws_root/.evtol-profile" ]]; then
        echo "ros_env.sh: .evtol-profile não encontrado em $ws_root." >&2
        echo "            Rode ./setup.sh --profile <nome> ou:" >&2
        echo "                echo <nome> > $ws_root/.evtol-profile" >&2
        echo "            Perfis: $("$ws_root/doctor.sh" --list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')" >&2
        return 1
    fi

    profile="$(tr -d '[:space:]' < "$ws_root/.evtol-profile")"
    profile_file="$ws_root/env/$profile.yaml"

    if [[ ! -f "$profile_file" ]]; then
        echo "ros_env.sh: perfil '$profile' não existe ($profile_file)." >&2
        return 1
    fi

    distro="$(python3 -c "
import yaml
spec = yaml.safe_load(open('$profile_file')) or {}
print((spec.get('ros') or {}).get('distro', ''))
" 2>/dev/null)"

    if [[ -z "$distro" ]]; then
        echo "ros_env.sh: o perfil '$profile' não declara ros.distro." >&2
        return 1
    fi

    if [[ ! -f "/opt/ros/$distro/setup.bash" ]]; then
        echo "ros_env.sh: ROS 2 $distro não encontrado (/opt/ros/$distro)." >&2
        echo "            O perfil '$profile' exige essa distro. Veja docs/SETUP.md." >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "/opt/ros/$distro/setup.bash"

    if [[ -f "$ws_root/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "$ws_root/install/setup.bash"
    fi

    return 0
}

_evtol_ros_env
