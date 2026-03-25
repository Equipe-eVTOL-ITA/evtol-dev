# evtol-dev

Meta repository for the eVTOL ITA workspace — documentation, templates, and guides.

This is **not** a ROS2 package. It is intentionally ignored by `colcon build`.

## Contents

| File | Description |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Workspace architecture, dependency model, and golden rules |
| [SETUP.md](SETUP.md) | Step-by-step setup guide for new team members |
| [templates/scripts/](templates/scripts/) | Template scripts to bootstrap new competition repos |

## How to use the templates

When creating a new competition repository:

```bash
# 1. Create the competition repo
mkdir -p src/my_competition/scripts

# 2. Copy templates
cp src/evtol-dev/templates/scripts/*.sh src/my_competition/scripts/

# 3. Customize:
#    - simulate.sh: add your Gazebo worlds and drone poses
#    - build.sh: add your package targets
#    - agent.sh: usually no changes needed
```
