#!/usr/bin/env bash
# =============================================================================
# collect.sh — levanta o ambiente DESTA máquina e imprime um rascunho de perfil.
# =============================================================================
#
# Rode na Jetson ou na Raspberry:
#
#     ./env/collect.sh > /tmp/perfil.yaml
#
# e traga o arquivo para revisão. Ele NÃO vira um perfil sozinho: os valores
# saem como observados, e alguém precisa decidir quais viram contrato e com
# que precisão. Um perfil gerado automaticamente e não revisado pina acidente
# junto com decisão.
#
# Só lê. Não instala nem altera nada.
# =============================================================================

set -uo pipefail

q() { command -v "$1" >/dev/null 2>&1; }
apt_ver() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || echo "AUSENTE"; }
pip_ver() { python3 -c "import importlib.metadata as m;print(m.version('$1'))" 2>/dev/null || echo "AUSENTE"; }

distro="${ROS_DISTRO:-$(ls /opt/ros 2>/dev/null | head -1)}"
[ -z "$distro" ] && distro="DESCONHECIDO"

echo "# Rascunho gerado por env/collect.sh em $(date -Iseconds)"
echo "# Máquina: $(hostname) | $(uname -m)"
echo "# REVISE antes de usar: nem todo valor observado deve virar contrato."
echo
echo "profile: REVISAR      # ex.: jetson-humble, rpi-jazzy"
echo "description: REVISAR"
echo "simulation: false     # companions não simulam"
echo
echo "os:"
echo "  distributor_id: $(lsb_release -is 2>/dev/null || echo REVISAR)"
echo "  release: \"$(lsb_release -rs 2>/dev/null || echo REVISAR)\""
echo "  python: \"$(python3 -c 'import sys;print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)\""
echo
echo "ros:"
echo "  distro: $distro"
echo

# --- plataforma ------------------------------------------------------------
echo "# --- Detectado nesta máquina -------------------------------------------"
if [ -f /etc/nv_tegra_release ]; then
    echo "# Jetson (L4T): $(head -1 /etc/nv_tegra_release)"
    q nvcc && echo "# CUDA: $(nvcc --version | grep -oP 'release \K[0-9.]+')" || echo "# CUDA: nvcc ausente"
    [ -f /etc/nv_tegra_release ] && echo "# JetPack: $(apt_ver nvidia-jetpack)"
fi
if grep -qi raspberry /proc/device-tree/model 2>/dev/null; then
    echo "# Raspberry Pi: $(tr -d '\0' < /proc/device-tree/model)"
    echo "# libcamera: $(apt_ver libcamera0)"
fi
echo

echo "apt:"
echo "  required:"
for p in ros-"$distro"-desktop ros-"$distro"-ros-base ros-"$distro"-cv-bridge \
         ros-"$distro"-vision-msgs python3-colcon-common-extensions \
         python3-vcstool python3-rosdep; do
    v=$(apt_ver "$p"); [ "$v" != "AUSENTE" ] && echo "    $p: \"$v\"   # observado"
done
echo
echo "  forbidden: {}   # REVISAR: variantes incompatíveis conhecidas desta plataforma"
echo
echo "pip:"
echo "  check_opencv_api: true"
echo "  required:"
for p in numpy opencv-python setuptools; do
    v=$(pip_ver "$p"); [ "$v" != "AUSENTE" ] && echo "    $p: \"$v\"   # observado"
done
echo "  forbidden:"
echo "    opencv-contrib-python: >-"
echo "      Conflita com opencv-python: os dois instalam o mesmo módulo cv2."
echo
echo "commands:"
for c in MicroXRCEAgent colcon vcs rosdep; do
    q "$c" && echo "  $c:" && echo "    expect_path: $(command -v $c)"
done
echo
echo "git_repos:"
for r in ~/PX4-Autopilot ~/Micro-XRCE-DDS-Agent ~/PX4-gazebo-models; do
    [ -d "$r/.git" ] && echo "  ${r/#$HOME/\~}:" && \
      echo "    expect_describe: \"$(git -C "$r" describe --tags --always 2>/dev/null)\"   # observado"
done

echo
echo "# --- Câmeras / aceleração (para preencher à mão) ------------------------"
for p in python3-libcamera; do echo "#   $p: $(apt_ver $p)"; done
for p in depthai torch torchvision ultralytics; do echo "#   $p (pip): $(pip_ver $p)"; done
