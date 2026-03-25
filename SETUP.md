# eVTOL ITA — Setup Guide

Complete guide to set up the development environment from scratch. After following this guide, you will be able to run PX4 drone simulations with Gazebo and control the drone using ROS2 nodes.

---

## Prerequisites

- **OS:** Ubuntu 22.04
- **ROS2:** Humble
- **Python:** 3.10+
- **CMake:** 3.16+

---

## 1. Install System Dependencies

```bash
sudo apt update
sudo apt install -y git cmake python3-colcon-common-extensions
pip install --user -U empy==3.3.4 pyros-genmsg setuptools==59.6.0
```

---

## 2. Install ROS2 Humble

```bash
sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

sudo apt install software-properties-common
sudo add-apt-repository universe
sudo apt update && sudo apt install curl -y

sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt update && sudo apt upgrade -y
sudo apt install ros-humble-desktop ros-dev-tools

# Add to bashrc so ROS2 is always available
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source /opt/ros/humble/setup.bash
```

---

## 3. Install QGroundControl

```bash
sudo usermod -a -G dialout $USER
sudo apt-get remove modemmanager -y
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl -y
sudo apt install libfuse2 libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor0 -y
```

Logout and login, then:

```bash
cd ~/Downloads
wget https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage
chmod +x ./QGroundControl.AppImage
```

---

## 4. Install PX4-Autopilot (with Gazebo)

```bash
cd ~
git clone --branch v1.15.4 --recursive --depth 1 https://github.com/PX4/PX4-Autopilot.git
bash ./PX4-Autopilot/Tools/setup/ubuntu.sh
```

Logout and login, then build SITL:

```bash
cd ~/PX4-Autopilot
make px4_sitl
```

> When prompted about submodule changes, type `y` and press ENTER.

### (Optional) Custom Gazebo Models

If the team uses custom Gazebo models:

```bash
cd ~/PX4-Autopilot/Tools/simulation/gz
git checkout main
git remote remove origin
git remote add origin https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git
git pull origin main --rebase
```

---

## 5. Install Micro-XRCE-DDS-Agent

```bash
cd ~
git clone https://github.com/eProsima/Micro-XRCE-DDS-Agent.git
cd Micro-XRCE-DDS-Agent
mkdir build && cd build
cmake ..
make
sudo make install
sudo ldconfig /usr/local/lib/
```

Verify installation:

```bash
MicroXRCEAgent --help
```

---

## 6. Set Up the Workspace

### 6.1 Create the workspace directory

```bash
mkdir -p ~/evtol/dev/src
cd ~/evtol/dev/src
```

### 6.2 Clone all repositories

```bash
# Meta repo (docs & templates)
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git

# Layer 1: Foundations
git clone https://github.com/PX4/px4_msgs.git -b release/1.15
git clone https://github.com/Auterion/px4-ros2-interface-lib.git -b 1.3.0 px4_ros2_interface
git clone https://github.com/Equipe-eVTOL-ITA/custom_msgs.git
git clone https://github.com/Equipe-eVTOL-ITA/fsm.git

# Layer 2: Drone Abstraction
git clone https://github.com/Equipe-eVTOL-ITA/drone_lib.git

# Layer 3: Reusable Components
git clone https://github.com/Equipe-eVTOL-ITA/stdstates.git
git clone https://github.com/Equipe-eVTOL-ITA/cv_nodes.git
git clone https://github.com/Equipe-eVTOL-ITA/camera_publisher.git

# Layer 4: Competitions
git clone https://github.com/Equipe-eVTOL-ITA/sae2026.git
```

### 6.3 Build everything

```bash
cd ~/evtol/dev
source /opt/ros/humble/setup.bash
colcon build --symlink-install --executor sequential
```

### 6.4 Source the workspace

```bash
source install/setup.bash
```

> **Tip:** Add this to `~/.bashrc` for convenience:
> ```bash
> echo "source ~/evtol/dev/install/setup.bash" >> ~/.bashrc
> ```

---

## 7. Running a Simulation

Running a simulation requires **3 terminals**. All commands assume you are in `~/evtol/dev`.

### Terminal 1: PX4 SITL + Gazebo

```bash
cd ~/evtol/dev
source install/setup.bash
bash src/sae2026/scripts/simulate.sh <world_name>
```

This launches the PX4 flight controller in Software-In-The-Loop mode with the Gazebo 3D simulator.

### Terminal 2: DDS Agent

```bash
cd ~/evtol/dev
bash src/sae2026/scripts/agent.sh
```

This bridges ROS2 topics with PX4's internal messaging (uORB).

### Terminal 3: Your ROS2 Node

```bash
cd ~/evtol/dev
source install/setup.bash
ros2 run <package_name> <node_name>
```

### Visual Summary

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Terminal 1   │     │   Terminal 2      │     │  Terminal 3   │
│              │     │                  │     │              │
│ PX4 SITL     │◄───►│ MicroXRCE Agent  │◄───►│ ROS2 Node    │
│ + Gazebo     │ uORB│   (DDS bridge)   │ DDS │ (your code)  │
└──────────────┘     └──────────────────┘     └──────────────┘
```

---

## Troubleshooting

### Build fails with out-of-memory (RAM)

If your PC freezes during `colcon build` (common with 16GB RAM), increase swap:

```bash
sudo swapoff -a
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
sudo chmod 0600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### MicroXRCEAgent not found

Ensure you ran `sudo make install` and `sudo ldconfig /usr/local/lib/` after building. The binary should be at `/usr/local/bin/MicroXRCEAgent`.

### Gazebo models not loading

Verify model paths:

```bash
echo $GAZEBO_MODEL_PATH
# Should include: ~/PX4-Autopilot/Tools/simulation/gz/models
```

The `simulate.sh` script sets these automatically.
