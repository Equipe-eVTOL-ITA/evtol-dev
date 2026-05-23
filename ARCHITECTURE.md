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

## Frames & Units Convention

Mixing coordinate frames is one of the highest-cost bugs in drone software. The rules below are part of the architectural contract.

### Frames

| World | Body | Used by |
|---|---|---|
| **NED** (north-east-down) | **FRD** (front-right-down) | PX4 and everything inside `drone_lib` that talks directly to PX4. |
| **ENU** (east-north-up) | **FLU** (front-left-up) | ROS 2 conventions — used by everything **above** `drone_lib` (`stdstates`, missions, CV, telemetry). |

`drone_lib` is the single boundary that converts between the two. **No package above `drone_lib` ever touches NED/FRD directly.** When you need a transform between frames, use **tf2** — never hand-rolled rotation matrices.

### `frame_id` on every header

- Every published message that has a `Header` MUST set a meaningful `frame_id`. **Empty `frame_id` is a bug.**
- Canonical frames in this workspace: `map`, `odom`, `base_link`, `camera_optical`, `vertical_camera_optical`.
- New frames need a documented parent (the tf tree must stay connected).

### Units

- **Distances:** meters.
- **Angles:** radians.
- **Time:** ROS time (`builtin_interfaces/Time` / `rclcpp::Time`). No bare seconds-since-epoch in message fields.
- **Velocity:** m/s for linear, rad/s for angular.
- If a field uses different units, encode it in the field name (e.g. `altitude_cm`, `heading_deg`) — but prefer the conventions above.

---

## Topic-Naming Convention

The workspace has grown organically and topic names are inconsistent. Going forward, **new topics MUST follow these rules**, and existing inconsistencies should be reconciled when packages are touched anyway.

### Rules

1. **Always start with `/`** (absolute paths). Relative topic names (`'centroid'`, `'ball_detection'`) inherit the node's namespace and become a debugging nightmare when nodes are remapped.
2. **Group by producer**, not by consumer:
   - `/drone/...` — drone state from `drone_lib` (`/drone/pose`, `/drone/twist`, `/drone/path`).
   - `/telemetry/...` — telemetry plumbing (`/telemetry/drone_status`, `/telemetry/logs`, `/telemetry/system_health`).
   - `/<detector_name>/...` — per-CV-node outputs (`/window_detector/mask`, `/base_detector/image`, `/mangueira/angle`).
   - `/camera/...`, `/vertical_camera/...` — raw camera streams. Always suffix encoding when applicable: `/image/raw`, `/image/compressed`.
3. **English-only topic names** when introducing new ones. Existing Portuguese names (`/mangueira/...`, `/fase1_vision/...`) can stay until the package is rewritten — don't rename in flight without coordination.
4. **No mission-phase prefixes on shared topics.** A name like `/fase1_vision/base_detection` ties a generic detector to a specific mission phase; prefer `/base_detector/...` and let missions subscribe.

### Discovering existing topics

When in doubt, run a node and `ros2 topic list` against a live system before naming a new one — avoids accidental collisions.

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

## Versioning Policy

The workspace is pinned via [evtol.repos](evtol.repos), which references **tags** on each repo. Versioning is intentionally light — full semantic versioning is overkill for an undergrad team.

### Tag scheme

Each team repo carries `vMAJOR.MINOR.PATCH` tags. Bumping rules:

| Bump | When to use | Example |
|---|---|---|
| **Patch** (`v0.1.0 → v0.1.1`) | Backwards-compatible fix; same API; safe to drop in. | A CV node bugfix; a typo fix in a state. |
| **Minor** (`v0.1.0 → v0.2.0`) | New feature or any change downstream packages must adopt. | New public method on `Drone`; new state in `stdstates`. |
| **Major** (`v0.x → v1.0`) | Deliberate "this is stable" declaration. Don't use yet — reserve for when an API is locked. |

### Tagging workflow

```bash
# On the branch you want to freeze (usually main):
git tag -a v0.2.0 -m "Brief note on what changed since v0.1.x"
git push origin v0.2.0
```

Then update [evtol.repos](evtol.repos) to pin the consumer repo to the new tag, and open a PR.

### What `evtol.repos` pins

- **Tags or commit hashes only.** Never branches (`main`, `jetson`, etc.) — branches move; pins must not.
- A separate `sae<year>.repos` lives in each competition repo to freeze exactly what flew that year.

---

## Git Workflow Practices

The team has historically not followed disciplined git practice — long-lived branches, sparse commits, and divergence between `main` and deployment branches (`jetson`, `bronco`, `angelo`, etc.) have caused real ambiguity about "which version is current." The rules below exist to prevent that.

### Branching

- **One feature = one branch = one person.** If two people want to work on the same feature, they pair on the same branch, not on parallel forks.
- **Each branch has an owner.** The owner is responsible for keeping it short-lived and merged. If you can't finish a branch, hand it off explicitly.
- **Name branches after the work**, not the person. `feat/h-pattern-search`, `fix/landing-overshoot` — not `angelo`, `jetson`.

### Commit cadence

- **Commit at every meaningful checkpoint** — at minimum once per work session, ideally several times. Long uncommitted work blocks teammates and risks losing hours to a crash.
- **One commit = one logical change.** If you have to use "and" in the commit message, split it.

### Branch lifetime

- **Open a PR within a few days of starting a branch.** A PR is the conversation about the work, not the celebration after.
- **Merge or close within ~1–2 weeks.** Branches older than this should be revisited: either finish them, or close them and capture what's worth keeping in an issue.
- **No "deployment branches".** `jetson`, `bronco`, etc. that diverge from `main` for weeks are an anti-pattern. If different machines need different code, that's a configuration concern (YAML, launch arg) — not a long-lived fork.

### What this looks like in practice

| Scenario | Right way | Wrong way (current practice we're moving away from) |
|---|---|---|
| New mission feature | Branch `feat/<name>` from `main`, PR within days, merge within a week. | Push directly to `jetson`; let it diverge from `main` for a month. |
| Hot fix needed on the drone | Branch `fix/<thing>` from `main`, PR, merge, **then** deploy. | Edit on the Jetson, commit there, forget to push for two weeks. |
| Two people on the same area | Coordinate; one branch with two committers, or split the work into independent branches. | Two parallel branches that quietly diverge. |
| Trying something risky | Branch, prototype, **close the branch** when the prototype is done (merged or abandoned). | Leave the branch around forever as "the place I was trying X". |

When the team consistently follows the rules above, `evtol.repos` stays a meaningful contract and `git log --all --graph` stays readable.

---

## Golden Rules

1. **Never duplicate code** — if something is reusable, it belongs in a lower layer package.
2. **Never use git submodules** — clone repos side-by-side (now via `vcstool` per [evtol.repos](evtol.repos)) and let `colcon` resolve dependencies.
3. **Competition repos are disposable** — they only contain mission-specific logic. All reusable code lives in shared packages.
4. **Communicate between nodes via ROS2 topics/services** — don't import Python code across packages directly.
5. **Each competition owns its scripts** — simulation configs live in the competition repo's `scripts/` folder.
6. **Nothing above `drone_lib` touches NED/FRD or `px4_msgs`** — `drone_lib` is the only PX4 boundary. See *Frames & Units Convention*.
7. **Pin tags, never branches** in `evtol.repos`. See *Versioning Policy*.
8. **No long-lived branches.** See *Git Workflow Practices*.
