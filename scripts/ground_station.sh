#!/bin/bash
# ==========================================================
# ground_station.sh — Generic ground station launcher
# Usage: ./scripts/ground_station.sh <mission_package>
# ==========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source /opt/ros/humble/setup.bash

if [ -f "$WORKSPACE_DIR/install/setup.bash" ]; then
    source "$WORKSPACE_DIR/install/setup.bash"
else
    echo "Error: Workspace not built. Run build first."
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <mission_package>"
    echo "Example: $0 mission_1"
    exit 1
fi

PACKAGE=$1

echo "Launching ground station for: $PACKAGE"
ros2 launch "$PACKAGE" ground_station.launch.py
