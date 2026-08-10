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
sudo apt install -y git cmake python3-colcon-common-extensions python3-vcstool python3-rosdep
pip install --user -U empy==3.3.4 pyros-genmsg 'setuptools<80' 'packaging>=23'
```

> **Por que `setuptools<80`.** O `colcon build --symlink-install` instala
> pacotes `ament_python` chamando `setup.py develop --editable`, e o
> **setuptools 80.0.0 removeu a opção `--editable`**. Com 80 ou mais recente o
> build morre no primeiro pacote Python com `error: option --editable not
> recognized`, e o colcon aborta sem processar os demais. Verificado: 80.0.0 e
> 83.0.0 falham; tudo abaixo de 80 funciona **desde que o `packaging` seja
> compatível** — veja a nota seguinte.
>
> A versão anterior deste guia pinava `setuptools==59.6.0`, que é a versão de
> sistema do Ubuntu 22.04 e não serve para o Python 3.12 do Ubuntu 24.04. A
> faixa `<80` vale nos dois. O `doctor.sh` confere isso.
>
> **E por que `packaging>=23`.** A partir do setuptools 71, ele chama uma
> função do `packaging` que só existe da versão 23 em diante. O Ubuntu 22.04
> traz `python3-packaging` **21.3** pelo apt, e a combinação quebra o build
> logo no primeiro pacote Python, com `canonicalize_version() got an
> unexpected keyword argument`. Os dois pins andam juntos — e o `doctor.sh`
> ainda roda um teste funcional que instala um pacote de mentira para
> confirmar que o caminho inteiro funciona.

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

### Modelos e mundos customizados do Gazebo

Necessário para simular os mundos das competições (`sae1_26`, `sae2_26`, ...).

Siga **[gazebo_models_setup.md](gazebo_models_setup.md)**.

> A instrução que existia aqui — trocar o `remote` de
> `Tools/simulation/gz` para o fork da equipe — **foi descontinuada**. Ela
> convivia com o método de symlinks descrito no outro documento, e o resultado
> foi máquina com os dois ao mesmo tempo, servindo mundos de commits diferentes
> do mesmo repositório sem nenhum sinal disso. Se a sua máquina tem o método
> antigo, o documento acima explica como voltar ao estado limpo.

---

## 5. Install Micro-XRCE-DDS-Agent

Pin to **v3.0.1** — a versão verificada nas máquinas do time que voam com
PX4 v1.15.4. O mesmo pin está declarado em `env/<perfil>.yaml` e é conferido
pelo `doctor.sh`; se você mudar aqui, mude lá também.

```bash
cd ~
git clone --branch v3.0.1 --depth 1 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git
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

## 6. Set Up the Workspace (one command)

After completing sections 1–5, bootstrap the entire workspace with two commands:

```bash
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git ~/evtol/dev
cd ~/evtol/dev && ./setup.sh --profile desktop-humble
```

> **O `evtol-dev` É a raiz do workspace.** Ele não é clonado dentro de `src/` —
> ele *é* `~/evtol/dev`. O `src/` é criado e preenchido pelo `vcs import`, e é
> ignorado pelo git deste repositório (cada repo em `src/` tem o seu próprio).
> Assim o `.vscode/`, os `scripts/` e os perfis ficam versionados no lugar onde
> são de fato usados, sem precisar copiar nada.

`setup.sh` faz, nesta ordem:

1. **Verifica o ambiente** contra `env/<perfil>.yaml` (`doctor.sh`) — e **para** se algo não confere.
2. Importa todos os repos nas versões pinadas em [evtol.repos](evtol.repos) (via `vcs import`).
3. Roda `rosdep install` para as dependências de sistema.
4. Compila com `colcon build --symlink-install --executor sequential`.

### Qual perfil usar

O perfil determina a distro do ROS, a versão do Gazebo, a variante do bridge e
os pins de apt/pip. Não existe padrão, de propósito: adivinhar errado é
exatamente o bug que isso veio eliminar.

| Perfil | Máquina |
|---|---|
| `desktop-humble` | PC de desenvolvimento e simulação (ROS 2 Humble, Gazebo Garden) |

Liste os disponíveis com `./doctor.sh --list`.

Depois da primeira execução bem-sucedida o perfil fica registrado em
`.evtol-profile`, e você pode chamar `./setup.sh` sem argumentos.

### Se o `doctor.sh` reprovar

Ele imprime a linha de correção de cada item. Corrija e rode de novo. Existe um
`--skip-doctor`, mas ele não serve para "resolver" a reprovação: cada checagem
existe porque aquele item já custou tempo ao time, e nenhuma delas é cosmética.
O caso clássico é o bridge Gazebo↔ROS — instalar a variante errada não gera
erro nenhum, só faz nenhum tópico do Gazebo chegar no ROS.

### 6.1 VSCode Tasks

Nada a fazer. O `.vscode/tasks.json` já está versionado na raiz do workspace,
que é exatamente onde o VSCode o procura:

```bash
code ~/evtol/dev
```

> Antes era preciso `cp -r src/evtol-dev/.vscode ~/evtol/dev/.vscode`. Toda
> cópia deriva da origem, e essa derivou: os scripts copiados para a raiz
> ficaram desatualizados, e um deles estava quebrado (resolvia `WORKSPACE_DIR`
> para fora do workspace). Por isso o `evtol-dev` passou a ser a própria raiz.

### 6.2 (Need a specific repo at a non-pinned version?)

To override a pin for local work, just `cd src/<repo>` and `git checkout` the branch or commit you want. The next `vcs import` will warn if local state diverges, but won't overwrite by default.

To add a *new* repo to the workspace permanently, edit [evtol.repos](evtol.repos) and re-run `setup.sh`.

---

## 7. Running a Simulation

### Option A: VSCode Tasks (recommended)

1. Open the workspace in VSCode: `code ~/evtol/dev`
2. Press `Ctrl+Shift+P` → **"Tasks: Run Task"**
3. Select **"simulation start"** → choose a world (e.g., `sae1`)
   - This launches PX4 + Gazebo, DDS Agent, and image bridge all at once
4. Press `Ctrl+Shift+P` → **"Tasks: Run Task"**
5. Select **"mission launch"** → choose a mission (e.g., `mission_1`)
6. When done, run the **"gazebo kill"** task to clean up

### Option B: Terminal (3 terminals)

All commands assume you are in `~/evtol/dev`.

**Terminal 1 — PX4 SITL + Gazebo:**

```bash
cd ~/evtol/dev
bash src/sae2026/scripts/simulate.sh sae1
```

**Terminal 2 — DDS Agent:**

```bash
cd ~/evtol/dev
bash src/sae2026/scripts/agent.sh
```

**Terminal 3 — Mission:**

```bash
cd ~/evtol/dev
source install/setup.bash

# Recommended: launch (loads YAML params + system_health)
ros2 launch mission_1 simulation.launch.py

# Alternative: run (direct, no YAML)
ros2 run mission_1 mission_1
```

### `ros2 launch` vs `ros2 run`

| | `ros2 run` | `ros2 launch` |
|---|---|---|
| Loads YAML config | ❌ | ✅ |
| Starts system_health | ❌ | ✅ |
| Best for | Quick tests | Full simulation |

### Architecture

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
echo $GZ_SIM_RESOURCE_PATH
# Should include: ~/PX4-Autopilot/Tools/simulation/gz/models
```

The `simulate.sh` script sets these automatically.

