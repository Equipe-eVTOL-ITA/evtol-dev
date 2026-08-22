# evtol-dev

**A raiz do workspace ROS 2 da equipe eVTOL ITA.**

Este repositório *é* `~/evtol/dev`. Ele não é um pacote ROS 2 e não é clonado
dentro de `src/` — o `src/` é criado e preenchido pelo `vcs import` a partir do
[evtol.repos](evtol.repos), e é ignorado pelo git daqui (cada repositório em
`src/` tem o seu próprio).

## Começando do zero

Pré-requisitos (ROS 2, PX4, Micro-XRCE-DDS-Agent, Gazebo): **[docs/SETUP.md](docs/SETUP.md)**.

Com eles prontos, o workspace inteiro sobe em dois comandos:

```bash
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git ~/evtol/dev
cd ~/evtol/dev && ./setup.sh --profile desktop-humble
```

## Conteúdo

| Caminho | O que é |
|---|---|
| [evtol.repos](evtol.repos) | Manifesto de **código** — quais repositórios, em quais tags |
| [env/](env/) | Manifesto de **ambiente** — um perfil por plataforma |
| [doctor.sh](doctor.sh) | Verifica se a máquina bate com o perfil declarado |
| [setup.sh](setup.sh) | Bootstrap: doctor → import → rosdep → build |
| [docs/GUIA.md](docs/GUIA.md) | **Comece por aqui** — como o workspace funciona e como criar uma competição nova |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | O contrato: camadas, frames, tópicos, ambiente, git |
| [docs/FSM.md](docs/FSM.md) | **Como fazer uma FSM** — do zero a um estado seu voando |
| [docs/BT.md](docs/BT.md) | **Como fazer uma Behavior Tree** — a árvore em XML e os nós da equipe |
| [docs/SETUP.md](docs/SETUP.md) | Instalação da máquina, do zero |
| [docs/VOO_SSH.md](docs/VOO_SSH.md) | **Voar pelo SSH** — rodar uma missão na Jetson do seu computador |
| [docs/gazebo_models_setup.md](docs/gazebo_models_setup.md) | Modelos e mundos customizados do Gazebo |
| [scripts/](scripts/) | Scripts genéricos do workspace — veja a tabela abaixo |
| [templates/scripts/](templates/scripts/) | Modelos para criar um repo de competição novo |
| [.vscode/tasks.json](.vscode/tasks.json) | Tasks do VSCode — já no lugar certo, sem cópia |

## Os scripts

Todos são chamados pelas tasks do VSCode, e todos funcionam direto no terminal.

| Script | O que faz |
|---|---|
| [scripts/build.sh](scripts/build.sh) | Compila um pacote, vários, `--all`, `--deps` ou `--changed` |
| [scripts/parar.sh](scripts/parar.sh) | Encerra a simulação inteira, com SIGINT antes de SIGKILL, e confere |
| [scripts/agent.sh](scripts/agent.sh) | Micro XRCE-DDS Agent — UDP na simulação, `--serial` no voo |
| [scripts/qgc.sh](scripts/qgc.sh) | Abre o QGroundControl, procurando o AppImage onde ele estiver |
| [scripts/ground_station.sh](scripts/ground_station.sh) | Sobe a estação de solo de uma missão |
| [scripts/sim2d.sh](scripts/sim2d.sh) | Simulador 2D; com `--com-missao`, sobe a missão junto |
| [scripts/image_bridge.sh](scripts/image_bridge.sh) | Câmeras do Gazebo → tópicos ROS 2 |
| [scripts/ros_env.sh](scripts/ros_env.sh) | Carrega o ROS da distro do perfil desta máquina (**sourcear**) |
| [scripts/processos.sh](scripts/processos.sh) | De que uma simulação é feita — lido pelo `parar.sh` |
| [scripts/sync_tasks.py](scripts/sync_tasks.py) | Regenera as listas das tasks a partir do que existe em `src/` |

Dois deles resolvem coisas que costumavam ser digitadas à mão:

```bash
./scripts/build.sh --changed        # compila só os repos com trabalho solto
./scripts/agent.sh --serial         # o agente em SERIAL, que é como o voo usa
```

## Os dois manifestos

O `evtol.repos` garante que todo mundo tem o mesmo **código**. Ele não tem como
garantir que todo mundo tem o mesmo **ambiente** — distro do ROS, versão do
Gazebo, variante do bridge, PX4, apt, pip. É sempre aí que nascem os bugs caros,
porque essa classe de erro não produz mensagem de erro: produz *"não funciona e
ninguém sabe por quê"*.

| Manifesto | Pina | Verificado por |
|---|---|---|
| `evtol.repos` | Código — repositórios git, em tags | `vcs import` |
| `env/<perfil>.yaml` | Ambiente — distro, Gazebo, bridge, PX4, apt, pip | `doctor.sh` |

```bash
./doctor.sh --list                      # perfis disponíveis (o atual leva '*')
./doctor.sh --current                   # em qual perfil ESTA máquina está
./doctor.sh --profile desktop-humble    # verifica esta máquina
```

Sai com código 0 se confere e 1 se não — por isso serve de portão no `setup.sh`
e no CI. Detalhes e as regras de edição em
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), seção *O Contrato de Ambiente*.

## Perfis

O time voa com **duas plataformas ao mesmo tempo**: um drone com Jetson Orin
Nano (Humble) e outro com Raspberry Pi (Jazzy). Numa mesma competição, algumas
fases rodam numa e outras na outra. Por isso a distro nunca é um valor fixo
dentro de script — vem do perfil, registrado em `.evtol-profile` (local, não
versionado). Em scripts e tasks, use:

```bash
source scripts/ros_env.sh
```

Para saber em qual perfil você está — a pergunta que aparece justamente quando
algo se comporta de forma inesperada:

```bash
./doctor.sh --current
```

Ou a task **perfil**. O `source scripts/ros_env.sh` também exporta
`EVTOL_PROFILE` no shell.

Se esta máquina guarda o QGroundControl num lugar próprio, declare-o no perfil
em vez de decorar o caminho:

```yaml
qgc:
  path: ~/Downloads/apps/QGroundControl-x86_64.AppImage
```

## Criando um repo de competição novo

```bash
mkdir -p src/minha_competicao/scripts
cp templates/scripts/*.sh src/minha_competicao/scripts/
# depois: simulate.sh (mundos e poses), build.sh (alvos).
# agent.sh normalmente não precisa de mudança.
```
