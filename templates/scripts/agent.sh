#!/bin/bash
# ==========================================================
# Template: agent.sh
# Starts the MicroXRCE-DDS Agent for simulation (UDP).
#
# Usage: ./scripts/agent.sh
#
# This script rarely needs customization. For hardware
# (serial) connections, change udp4 to serial and set the
# appropriate device path.
# ==========================================================
set -e

source /opt/ros/humble/setup.bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [ -f "$WORKSPACE_DIR/install/setup.bash" ]; then
    source "$WORKSPACE_DIR/install/setup.bash"
fi

echo "Starting MicroXRCE-DDS Agent for SIMULATION (UDP)"

export PATH=$PATH:/usr/local/bin

if command -v MicroXRCEAgent &> /dev/null; then
    MicroXRCEAgent udp4 -p 8888
elif [ -f /usr/local/bin/MicroXRCEAgent ]; then
    /usr/local/bin/MicroXRCEAgent udp4 -p 8888
elif [ -f ~/Micro-XRCE-DDS-Agent/build/MicroXRCEAgent ]; then
    ~/Micro-XRCE-DDS-Agent/build/MicroXRCEAgent udp4 -p 8888
else
    echo "Error: MicroXRCEAgent not found. Please install it first."
    echo "See docs/SETUP.md for installation instructions."
    exit 1
fi
