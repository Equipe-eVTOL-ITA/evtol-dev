#!/bin/bash
# ==========================================================
# image_bridge.sh — Generic
# Bridges Gazebo camera images to ROS2 topics.
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Nunca `source /opt/ros/humble/setup.bash` aqui: o time voa com Humble na
# Jetson e Jazzy na Raspberry, e um "humble" escrito à mão neste arquivo quebra
# metade das máquinas sem dizer por quê. O ros_env.sh resolve a distro pelo
# perfil, e já carrega o install/ do workspace.
# shellcheck source=scripts/ros_env.sh
source "$WORKSPACE_DIR/scripts/ros_env.sh"

echo "Starting ros_gz_image bridge (vertical_camera & horizontal_camera → ROS2)"
ros2 run ros_gz_image image_bridge /vertical_camera /horizontal_camera --ros-args -p transport:=compressed
