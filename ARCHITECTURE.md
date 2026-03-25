# eVTOL ITA — Workspace Architecture

This document explains the project structure, how dependencies work, and how to reuse code across ROS2 packages.

> For first-time setup instructions, see [SETUP.md](SETUP.md).

---

## Overview

The workspace follows a **flat repos + colcon** pattern: each GitHub repository is cloned side-by-side in the `src/` directory, and ROS2's build system (`colcon`) automatically resolves dependencies between them.

```
~/
├── PX4-Autopilot/                      ← PX4 firmware + Gazebo (external)
├── Micro-XRCE-DDS-Agent/              ← DDS agent (external)
│
└── evtol/
    └── dev/                            ← colcon workspace root
        ├── src/                        ← all repos cloned here (flat)
        │   ├── evtol-dev/              ← meta repo — docs & templates (NOT a ROS2 package)
        │   │   ├── ARCHITECTURE.md
        │   │   ├── SETUP.md
        │   │   └── templates/scripts/
        │   ├── px4_msgs/               ← 3rd party — PX4 message definitions
        │   ├── px4_ros2_interface/     ← 3rd party — PX4-ROS2 interface library
        │   ├── custom_msgs/            ← shared message/service definitions
        │   ├── fsm/                    ← finite state machine framework
        │   │   ├── fsm/                ← ROS2 package (the library)
        │   │   └── fsm_demo/           ← ROS2 package (demo/examples)
        │   ├── drone_lib/              ← Drone class + PID + movement + transforms
        │   ├── stdstates/              ← standard FSM states (takeoff, landing, waypoints)
        │   ├── cv_nodes/               ← computer vision solutions
        │   │   ├── qrcode_detector/    ← ROS2 package
        │   │   └── window_detector/    ← ROS2 package
        │   ├── camera_publisher/       ← camera image publisher
        │   ├── sae2026/                ← SAE 2026 competition
        │   │   ├── scripts/            ← competition-specific simulation scripts
        │   │   └── mission_1/          ← ROS2 package
        │   ├── telemetry_handler/      ← (independent project)
        │   └── treinamento_2026/       ← (independent project)
        ├── build/                      ← colcon build artifacts (auto-generated)
        ├── install/                    ← colcon install space (auto-generated)
        └── log/                        ← colcon build logs (auto-generated)
```

---

## External Dependencies

These tools live **outside** the colcon workspace and are required for simulation:

| Tool | Location | Purpose |
|---|---|---|
| **PX4-Autopilot** | `~/PX4-Autopilot` | Flight controller firmware (v1.15.4). Also installs Gazebo for simulation. |
| **Micro-XRCE-DDS-Agent** | `~/Micro-XRCE-DDS-Agent` | Translates ROS2 topics ↔ PX4 uORB topics. After build, binary is at `/usr/local/bin/MicroXRCEAgent`. |
| **Gazebo** | Installed via PX4 | 3D simulation environment. Models and worlds in `~/PX4-Autopilot/Tools/simulation/gz/`. |
| **QGroundControl** | `~/Downloads/QGroundControl.AppImage` | Ground control station for monitoring/commanding the drone. |

> **Why `~/`?** PX4-Autopilot's internal scripts assume `~/PX4-Autopilot`. Keeping it there avoids path issues.

---

## The 4-Layer Dependency Model

The packages are organized in layers. **Lower layers never depend on upper layers.**

```
┌───────────────────────────────────────────────────┐
│  Layer 4: Competition-Specific                    │
│  sae2026/mission_1, sae2026/mission_2, ...        │
│  (Uses everything below. Never reused elsewhere.) │
├───────────────────────────────────────────────────┤
│  Layer 3: Reusable Components                     │
│  stdstates, cv_nodes, camera_publisher            │
│  (Reusable across competitions.)                  │
├───────────────────────────────────────────────────┤
│  Layer 2: Drone Abstraction                       │
│  drone_lib (Drone + PID + movement + transforms)  │
│  (Human-friendly API over PX4.)                   │
├───────────────────────────────────────────────────┤
│  Layer 1: Foundations                             │
│  fsm, custom_msgs, px4_msgs, px4_ros2_interface   │
│  (Core libraries with zero team dependencies.)    │
└───────────────────────────────────────────────────┘
```

### What this means in practice

- `mission_1` can use `fsm`, `drone_lib`, `stdstates`, and `cv_nodes`.
- `stdstates` can use `fsm` and `drone_lib`, but **not** `mission_1`.
- `drone_lib` can use `px4_msgs` and `custom_msgs`, but **not** `stdstates`.
- `fsm` depends on nothing from the team — it's a generic library.

---

## Package Reference

| Package | What it provides | Language |
|---|---|---|
| `fsm` | Finite state machine framework (`State`, `StateMachine`) | C++ |
| `custom_msgs` | Shared ROS2 message/service definitions | CMake (msg gen) |
| `drone_lib` | `Drone` class (PX4), `PidController`, `Movement`, `Transformations` | C++ |
| `stdstates` | `TakeoffState`, `LandingState`, `NextWaypoints` | C++ |
| `cv_nodes/*` | Vision nodes (`qrcode_detector`, `window_detector`) | Python |
| `camera_publisher` | Camera image publisher node | Python |

---

## Competition Scripts

Each competition repository contains a `scripts/` directory with simulation scripts specific to that competition. This keeps each competition self-contained.

### Standard script structure

```
<competition>/
├── scripts/
│   ├── simulate.sh     ← launches PX4 SITL + Gazebo with competition worlds
│   ├── agent.sh        ← starts MicroXRCE-DDS Agent
│   └── build.sh        ← builds workspace packages for this competition
├── mission_1/          ← ROS2 package
├── mission_2/          ← ROS2 package
└── README.md
```

### What each script does

| Script | Purpose | Example |
|---|---|---|
| `simulate.sh <world>` | Sets Gazebo model/world paths, launches PX4 SITL with the given world | `./scripts/simulate.sh mission_1_world` |
| `agent.sh` | Starts `MicroXRCEAgent udp4 -p 8888` for simulation | `./scripts/agent.sh` |
| `build.sh <target>` | Runs `colcon build` with preset targets (`all`, `deps`, `mission_1`, etc.) | `./scripts/build.sh all` |

> **Template scripts** are available in `src/evtol-dev/templates/scripts/` for bootstrapping new competitions.

---

## How ROS2 Dependencies Work

### Declaring dependencies

Each ROS2 package has a `package.xml` that declares which other packages it needs. For example, `mission_1/package.xml`:

```xml
<package format="3">
  <name>mission_1</name>
  ...
  <depend>rclcpp</depend>       <!-- ROS2 C++ client library -->
  <depend>fsm</depend>          <!-- our FSM framework -->
  <depend>drone_lib</depend>    <!-- our Drone class + utilities -->
  <depend>stdstates</depend>    <!-- our standard states -->
  <depend>px4_msgs</depend>     <!-- PX4 message types -->
  <depend>custom_msgs</depend>  <!-- our custom messages -->
  ...
</package>
```

When you run `colcon build`, it reads all `package.xml` files, builds a dependency graph, and compiles packages in the correct order automatically.

### Using a dependency in CMakeLists.txt

After declaring it in `package.xml`, use it in your `CMakeLists.txt`:

```cmake
# Find the dependency
find_package(fsm REQUIRED)
find_package(drone_lib REQUIRED)
find_package(stdstates REQUIRED)

# Create your executable
add_executable(mission_1_node src/mission_1_node.cpp)

# Link against the dependencies
ament_target_dependencies(mission_1_node
  rclcpp
  fsm
  drone_lib
  stdstates
  px4_msgs
  custom_msgs
)
```

### Including headers in C++ code

Once dependencies are declared, you can include their headers:

```cpp
// From fsm package
#include "fsm/state.hpp"
#include "fsm/state_machine.hpp"

// From drone_lib package — the Drone class
#include "drone/Drone.hpp"

// From drone_lib package — utilities
#include "drone/PidController.hpp"
#include "drone/movement.hpp"
#include "drone/transformations.hpp"

// From stdstates package — pre-built FSM states
#include "stdstates/takeoff_state.hpp"
#include "stdstates/landing_state.hpp"
#include "stdstates/next_waypoints.hpp"
```

### Python packages

For Python packages (like `cv_nodes`), dependencies are declared the same way in `package.xml`, but the build system is `ament_python`:

```xml
<export>
  <build_type>ament_python</build_type>
</export>
```

To use a Python ROS2 node from another package, you don't import it directly — you communicate via **ROS2 topics, services, or actions**. Each node runs independently and exchanges data through the ROS2 middleware.

---

## How To Add a New Mission

1. Create a new directory inside the competition repo:
   ```bash
   mkdir -p src/sae2026/mission_2/{src,include/mission_2,launch}
   ```

2. Create `package.xml` with needed dependencies:
   ```xml
   <package format="3">
     <name>mission_2</name>
     <version>0.0.1</version>
     <description>SAE 2026 — Mission 2</description>
     <maintainer email="your@email.com">Your Name</maintainer>
     <license>MIT</license>

     <buildtool_depend>ament_cmake</buildtool_depend>
     <depend>rclcpp</depend>
     <depend>fsm</depend>
     <depend>drone_lib</depend>
     <depend>stdstates</depend>

     <export>
       <build_type>ament_cmake</build_type>
     </export>
   </package>
   ```

3. Create `CMakeLists.txt` following the same pattern as `mission_1`.

4. Build:
   ```bash
   colcon build --packages-select mission_2
   ```

---

## How To Add a New Competition

1. Create a new repo (e.g., `cbr2026`) with the same structure:
   ```
   cbr2026/
   ├── scripts/          ← copy templates from evtol-dev/templates/scripts/
   │   ├── simulate.sh   ← customize worlds and models
   │   ├── agent.sh
   │   └── build.sh      ← customize build targets
   ├── mission_1/        ← ROS2 package
   ├── mission_2/        ← ROS2 package
   ├── README.md
   └── .gitignore
   ```

2. Clone it into `src/` alongside everything else.

3. All shared packages (`fsm`, `drone_lib`, `stdstates`, `cv_nodes`) are instantly available — just declare them in `package.xml`.

4. Customize `scripts/simulate.sh` with the competition's Gazebo worlds and drone models.

---

## How To Add a New CV Node

1. Create a new Python ROS2 package inside `cv_nodes/`:
   ```bash
   cd src/cv_nodes
   ros2 pkg create --build-type ament_python <detector_name> --dependencies rclpy sensor_msgs cv_bridge
   ```

2. Implement the node. It subscribes to camera topics and publishes detection results.

3. Any competition mission can use it by subscribing to its published topics — no code duplication needed.

---

## Useful Commands

```bash
# Build everything
colcon build --symlink-install

# Build a specific package and its dependencies
colcon build --packages-up-to mission_1

# Build only a specific package (dependencies must be built already)
colcon build --packages-select mission_1

# See the dependency graph
colcon graph --dot | dot -Tpng -o graph.png

# Clean build artifacts for a package
rm -rf build/mission_1 install/mission_1

# List all packages in the workspace
colcon list
```

---

## Golden Rules

1. **Never duplicate code** — if something is reusable, it belongs in a lower layer package.
2. **Never use git submodules** — clone repos side-by-side and let `colcon` resolve dependencies.
3. **Competition repos are disposable** — they only contain mission-specific logic. All reusable code lives in shared packages.
4. **Communicate between nodes via ROS2 topics/services** — don't import Python code across packages directly.
5. **Each competition owns its scripts** — simulation configs live in the competition repo's `scripts/` folder.
