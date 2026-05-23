#!/usr/bin/env bash
# eVTOL ITA workspace bootstrap.
#
# Run from the workspace root (e.g. ~/evtol/dev) after cloning evtol-dev:
#     mkdir -p ~/evtol/dev && cd ~/evtol/dev
#     git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git src/evtol-dev
#     ./src/evtol-dev/setup.sh
#
# Imports every team repo at its pinned version (per evtol.repos), installs
# rosdep deps, and builds. Non-ROS prerequisites (PX4-Autopilot,
# Micro-XRCE-DDS-Agent, optional PX4-gazebo-models) must be installed first
# per SETUP.md sections 4-5.

set -euo pipefail

# Resolve the workspace root: setup.sh lives at <ws_root>/src/evtol-dev/setup.sh.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/../.." && pwd)"
cd "$ws_root"

echo "==> Workspace root: $ws_root"

if [[ ! -f "src/evtol-dev/evtol.repos" ]]; then
    echo "ERROR: src/evtol-dev/evtol.repos not found." >&2
    echo "       Expected to find the manifest at the path above." >&2
    exit 1
fi

for tool in vcs colcon rosdep; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool '$tool' is not on PATH." >&2
        echo "       See SETUP.md sections 1-2 for prerequisites." >&2
        exit 1
    fi
done

if [[ -z "${ROS_DISTRO:-}" ]]; then
    if [[ -f /opt/ros/humble/setup.bash ]]; then
        # shellcheck disable=SC1091
        source /opt/ros/humble/setup.bash
    else
        echo "ERROR: ROS 2 Humble not found at /opt/ros/humble/setup.bash." >&2
        echo "       See SETUP.md section 2." >&2
        exit 1
    fi
fi

echo "==> Importing repositories (vcs import src < src/evtol-dev/evtol.repos)"
vcs import src < src/evtol-dev/evtol.repos

echo "==> Installing rosdep dependencies"
if ! rosdep update >/dev/null 2>&1; then
    echo "WARN: 'rosdep update' failed. If this is the first run, do once:"
    echo "         sudo rosdep init && rosdep update"
fi
rosdep install --from-paths src --ignore-src -y --rosdistro "${ROS_DISTRO:-humble}" || \
    echo "WARN: rosdep reported errors above — review before proceeding."

echo "==> Building workspace (colcon build --symlink-install --executor sequential)"
# --executor sequential avoids RAM spikes on 16GB-class machines (see SETUP.md troubleshooting).
colcon build --symlink-install --executor sequential

echo
echo "Build complete. In each new shell, source the workspace:"
echo "    source /opt/ros/humble/setup.bash"
echo "    source $ws_root/install/setup.bash"
