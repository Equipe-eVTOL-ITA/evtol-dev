#!/usr/bin/env bash
# =============================================================================
# Template: simulate.sh — sobe o PX4 SITL + Gazebo para um mundo.
# =============================================================================
#
#   ./scripts/simulate.sh <mundo>
#
# Copie para o scripts/ da sua competição e preencha o bloco `case` com os
# mundos, modelos e poses iniciais dela. É o ÚNICO arquivo dos três templates
# que exige customização de verdade.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# <ws>/src/<competicao>/scripts/  ->  <ws>
ws_root="$(cd "$script_dir/../../.." && pwd)"

# Carrega a distro do perfil desta máquina + o install/ do workspace.
# Nunca escreva `source /opt/ros/humble/setup.bash` aqui: o time voa com
# Jetson (Humble) e Raspberry Pi (Jazzy), e o mesmo script tem que servir aos
# dois. Veja docs/ARCHITECTURE.md, "O Contrato de Ambiente".
source "$ws_root/scripts/ros_env.sh"

# O PX4 lê os .sdf da própria árvore; o gz moderno usa GZ_SIM_RESOURCE_PATH
# (as variáveis GAZEBO_* são do Gazebo clássico e NÃO funcionam aqui).
export GZ_SIM_RESOURCE_PATH="${GZ_SIM_RESOURCE_PATH:-}:\
$HOME/PX4-Autopilot/Tools/simulation/gz/models:\
$HOME/PX4-Autopilot/Tools/simulation/gz/worlds:\
$HOME/PX4-gazebo-models/models:\
$HOME/PX4-gazebo-models/worlds"

cd "$HOME/PX4-Autopilot"

PX4_SYS_AUTOSTART=4001

case "${1:-}" in
    # ---- CUSTOMIZE: os mundos da sua competição -------------------------
    # fase1)
    #     PX4_GZ_WORLD=fase1_27                       # nome do .sdf
    #     PX4_GZ_MODEL_POSE="0.0, 0.0, 0.05, 0.0, 0.0, 0.0"   # x,y,z,r,p,y
    #     PX4_SIM_MODEL=x500_sae                      # modelo do drone
    #     ;;
    default)
        PX4_GZ_WORLD=default
        PX4_GZ_MODEL_POSE="0.0, 0.0, 0.05, 0.0, 0.0, 0.0"
        PX4_SIM_MODEL=x500
        ;;
    *)
        echo "Mundo desconhecido: '${1:-}'" >&2
        echo "Uso: $0 <mundo>" >&2
        echo "Disponíveis: default   (edite este script para adicionar os seus)" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Confere que o mundo e o modelo existem ANTES de chamar o PX4.
#
# Sem isto, o PX4 falha com uma mensagem que aponta para o lugar errado:
#
#     Unable to find or download file
#     ERROR [gz_bridge] Service call timed out. Check GZ_SIM_RESOURCE_PATH
#     ERROR [init] gz_bridge failed to start and spawn model
#
# ...o que faz todo mundo ir mexer no GZ_SIM_RESOURCE_PATH, quando a causa
# quase sempre e outra: o .sdf existe em ~/PX4-gazebo-models mas nao foi
# symlinkado para dentro do PX4. Os symlinks sao feitos uma vez; arquivo novo
# adicionado depois nao ganha symlink sozinho.
# ---------------------------------------------------------------------------
px4_gz="$HOME/PX4-Autopilot/Tools/simulation/gz"
faltando=0

if [[ ! -e "$px4_gz/worlds/$PX4_GZ_WORLD.sdf" ]]; then
    echo "ERRO: mundo '$PX4_GZ_WORLD.sdf' nao encontrado em" >&2
    echo "      $px4_gz/worlds/" >&2
    if [[ -e "$HOME/PX4-gazebo-models/worlds/$PX4_GZ_WORLD.sdf" ]]; then
        echo "      -> existe em ~/PX4-gazebo-models, so falta o symlink:" >&2
        echo "         ln -sf ~/PX4-gazebo-models/worlds/$PX4_GZ_WORLD.sdf \\" >&2
        echo "                $px4_gz/worlds/" >&2
    else
        echo "      -> nao existe nem em ~/PX4-gazebo-models. Crie o .sdf la." >&2
    fi
    faltando=1
fi

if [[ ! -e "$px4_gz/models/$PX4_SIM_MODEL" ]]; then
    echo "ERRO: modelo '$PX4_SIM_MODEL' nao encontrado em" >&2
    echo "      $px4_gz/models/" >&2
    if [[ -e "$HOME/PX4-gazebo-models/models/$PX4_SIM_MODEL" ]]; then
        echo "      -> existe em ~/PX4-gazebo-models, so falta o symlink:" >&2
        echo "         ln -sfn ~/PX4-gazebo-models/models/$PX4_SIM_MODEL \\" >&2
        echo "                 $px4_gz/models/$PX4_SIM_MODEL" >&2
    else
        echo "      -> nao existe nem em ~/PX4-gazebo-models. Crie o modelo la." >&2
    fi
    faltando=1
fi

if (( faltando )); then
    echo >&2
    echo "Veja docs/gazebo_models_setup.md." >&2
    exit 1
fi

PX4_SYS_AUTOSTART=$PX4_SYS_AUTOSTART \
PX4_GZ_MODEL_POSE=$PX4_GZ_MODEL_POSE \
PX4_GZ_WORLD=$PX4_GZ_WORLD \
PX4_SIM_MODEL=$PX4_SIM_MODEL \
./build/px4_sitl_default/bin/px4
