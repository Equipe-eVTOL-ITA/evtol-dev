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

    # A distro vem do doctor.py, e NAO de um yaml.safe_load daqui.
    #
    # Este script ja teve o seu proprio parser de YAML. Funcionava ate os
    # perfis ganharem heranca (`extends`) e `ros.distro` passar a morar na base
    # comum: o parser local nao sabia resolver isso, e TODA task do VSCode
    # passou a falhar com "o perfil nao declara ros.distro" -- enquanto o
    # doctor seguia verde, porque so ele tinha aprendido.
    #
    # Uma implementacao so de "ler o perfil". Nao volte a duplicar aqui.
    distro="$(python3 "$ws_root/env/doctor.py" --get ros.distro --profile "$profile" 2>/dev/null)"

    if [[ -z "$distro" ]]; then
        echo "ros_env.sh: o perfil '$profile' não declara ros.distro." >&2
        return 1
    fi

    if [[ ! -f "/opt/ros/$distro/setup.bash" ]]; then
        echo "ros_env.sh: ROS 2 $distro não encontrado (/opt/ros/$distro)." >&2
        echo "            O perfil '$profile' exige essa distro. Veja docs/SETUP.md." >&2
        return 1
    fi

    # Os setup.bash do ROS e do colcon leem variaveis nao definidas
    # (AMENT_TRACE_SETUP_FILES, COLCON_TRACE, ...). Se quem nos deu `source`
    # roda com `set -u` -- como todo script bem escrito do time --, isso
    # aborta. Suspendemos `nounset` so durante o sourcing e restauramos depois.
    local had_u=0
    [[ $- == *u* ]] && { had_u=1; set +u; }

    # shellcheck disable=SC1090
    source "/opt/ros/$distro/setup.bash"

    if [[ -f "$ws_root/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "$ws_root/install/setup.bash"
    fi

    (( had_u )) && set -u

    return 0
}

_evtol_ros_env
