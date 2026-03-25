#!/bin/bash
# ==========================================================
# Template: simulate.sh
# Launches PX4 SITL + Gazebo for a given world.
#
# Usage: ./scripts/simulate.sh <world_name>
#
# Copy this file to your competition's scripts/ directory
# and customize the case block with your competition's
# worlds, drone models, and spawn positions.
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ -f "$WORKSPACE_DIR/install/setup.bash" ]; then
    source "$WORKSPACE_DIR/install/setup.bash"
fi

export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:~/PX4-Autopilot/Tools/simulation/gz/models
export GAZEBO_RESOURCE_PATH=$GAZEBO_RESOURCE_PATH:~/PX4-Autopilot/Tools/simulation/gz/worlds

cd ~/PX4-Autopilot

PX4_SYS_AUTOSTART=4001
PX4_GZ_WORLD=$1

case $1 in
    # ---- CUSTOMIZE: Add your competition worlds here ----
    # example_world)
    #     PX4_GZ_MODEL_POSE="0.0, 0.0, 0.05, 0.0, 0.0, 0.0"
    #     PX4_SIM_MODEL=x500_simulation
    #     ;;
    *)
        echo "Unknown world: $1"
        echo "Usage: $0 <world_name>"
        echo ""
        echo "Available worlds:"
        echo "  (none configured — edit this script to add your worlds)"
        exit 1
        ;;
esac

PX4_SYS_AUTOSTART=$PX4_SYS_AUTOSTART \
PX4_GZ_MODEL_POSE=$PX4_GZ_MODEL_POSE \
PX4_GZ_WORLD=$PX4_GZ_WORLD \
PX4_SIM_MODEL=$PX4_SIM_MODEL \
./build/px4_sitl_default/bin/px4
