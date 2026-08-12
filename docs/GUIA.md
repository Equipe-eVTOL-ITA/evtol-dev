# Guia do Workspace eVTOL ITA

Tudo o que você precisa para trabalhar neste workspace com autonomia: como ele é
organizado, por que é assim, e o passo a passo para começar uma competição nova
do zero.

Se você só quer instalar a máquina, vá direto para [SETUP.md](SETUP.md). Se quer
entender as regras de arquitetura (camadas, frames, tópicos), veja
[ARCHITECTURE.md](ARCHITECTURE.md). Este documento é a ponte entre os dois.

---

## Índice

1. [O problema que este workspace resolve](#1-o-problema-que-este-workspace-resolve)
2. [Estrutura do workspace](#2-estrutura-do-workspace)
3. [Os dois manifestos](#3-os-dois-manifestos)
4. [Perfis de plataforma](#4-perfis-de-plataforma)
5. [Os scripts](#5-os-scripts)
6. [O CI](#6-o-ci)
7. [Rotina do dia a dia](#7-rotina-do-dia-a-dia)
8. [**Começando uma competição nova, do zero**](#8-começando-uma-competição-nova-do-zero)
9. [Quando algo dá errado](#9-quando-algo-dá-errado)

---

## 1. O problema que este workspace resolve

Um workspace ROS 2 é fácil de montar e difícil de manter **igual entre máquinas**.
O time voa com dois drones — um com Jetson Orin Nano, outro com Raspberry Pi — e
desenvolve num terceiro computador. Historicamente, o que mais custou tempo não
foram bugs de lógica: foram diferenças invisíveis de ambiente.

Casos reais, todos diagnosticados depois de horas ou dias:

| O que aparecia | O que era |
|---|---|
| Nenhum tópico do Gazebo chegava no ROS | Variante errada do bridge instalada. Rodava sem erro e não enxergava nada. |
| Código parou de funcionar sem ninguém ter mexido | Distro do ROS trocada entre Humble e Jazzy. |
| Precisava editar o código à mão depois de subir pro drone | OpenCV diferente entre dev e drone; funções com nome levemente diferente. |
| `colcon build` falhava no primeiro pacote Python | `setuptools` novo removeu uma opção que o `--symlink-install` usa. |
| Todos os detectores de visão mortos | `numpy 2` quebra o `cv_bridge` do Humble. A mensagem de erro não cita numpy. |

O que essas cinco têm em comum: **nenhuma produz uma mensagem de erro que aponte
para a causa**. Elas produzem *"não funciona e ninguém sabe por quê"*.

Quase tudo neste workspace existe para tornar essa classe de problema
**impossível de acontecer em silêncio**.

---

## 2. Estrutura do workspace

O repositório `evtol-dev` **é** a raiz do workspace. Ele não fica dentro de
`src/` — ele *é* `~/evtol/dev`.

```
~/evtol/dev/                    ← este repositório
├── evtol.repos                 ← manifesto de CÓDIGO
├── env/                        ← manifesto de AMBIENTE
│   ├── desktop-humble.yaml
│   ├── doctor.py
│   ├── cv_api_contract.py
│   └── collect.sh
├── doctor.sh                   ← verifica a máquina
├── setup.sh                    ← bootstrap
├── scripts/                    ← scripts genéricos do workspace
├── templates/scripts/          ← modelos para competições novas
├── docs/                       ← esta pasta
├── .vscode/tasks.json          ← tasks, já onde o VSCode lê
├── .evtol-profile              ← perfil DESTA máquina (não versionado)
│
├── src/                        ← gitignorado; preenchido por `vcs import`
│   ├── custom_msgs/            ← mensagens compartilhadas
│   ├── fsm/                    ← framework de máquina de estados
│   ├── drone_lib/              ← classe Drone (abstração do PX4)
│   ├── stdstates/              ← estados reutilizáveis (takeoff, landing, PID)
│   ├── cv_nodes/               ← nós de visão computacional
│   ├── camera_publisher/       ← publicação de câmera
│   ├── telemetry_handler/      ← telemetria
│   ├── px4_msgs/               ← 3rd party
│   ├── px4_ros2_interface/     ← 3rd party
│   └── sae2026/                ← uma competição
│
├── build/  install/  log/      ← saídas do colcon, gitignorados
```

### Por que `src/` é gitignorado

Cada repositório em `src/` tem o **seu próprio** git. Se este repositório
também versionasse o conteúdo deles, teríamos duas fontes da verdade para o
mesmo código — que é como o workspace antigo acumulou cópias renomeadas das
bibliotecas (`sae_drone_lib`, `itajuba_drone_lib`, ...). O `vcs import` traz
cada repositório na versão certa, e pronto.

E é por isso que **não usamos submódulos**. Está nas Golden Rules do
[ARCHITECTURE.md](ARCHITECTURE.md).

### O modelo em camadas

Dependências apontam **só para baixo**:

```
competições (sae2026, ...)          ← fina: só missões e configuração
       ↑
stdstates · cv_nodes · camera_publisher
       ↑
    drone_lib                        ← única fronteira com o PX4
       ↑
custom_msgs · fsm · px4_msgs
```

Duas consequências práticas:

- **Nada acima do `drone_lib` fala com o PX4 diretamente.** Nem `px4_msgs`, nem
  NED/FRD. Todo controle passa pela classe `Drone`.
- **Repositório de competição é descartável.** Se ele está crescendo muito, é
  sinal de que alguma capacidade genérica está no lugar errado e deveria descer
  para `stdstates` / `cv_nodes`.

---

## 3. Os dois manifestos

Esta é a ideia central do workspace. Vale entender bem.

| Manifesto | Pina | Verificado por |
|---|---|---|
| `evtol.repos` | **Código** — quais repositórios, em quais tags | `vcs import` |
| `env/<perfil>.yaml` | **Ambiente** — distro do ROS, Gazebo, bridge, PX4, apt, pip | `doctor.sh` |

### `evtol.repos`

Lista cada repositório e a **tag** exata:

```yaml
repositories:
  drone_lib:
    type: git
    url: https://github.com/Equipe-eVTOL-ITA/drone_lib.git
    version: v0.2.0
```

**Sempre tag, nunca branch.** Um branch anda: no dia em que alguém commitar na
`main`, todo mundo que rodar `vcs import` passa a receber código diferente sem
ter mudado nada. Uma tag é congelada.

### `env/<perfil>.yaml`

Um `.repos` pina **apenas repositórios git**. Ele é estruturalmente incapaz de
pinar a distro do ROS, a versão do Gazebo, a variante do bridge ou os pacotes de
apt e pip — que é exatamente onde estavam todos os bugs da tabela da seção 1.

O perfil preenche essa metade. Além dos pacotes **obrigatórios**, ele declara
uma lista de **proibidos** — e é aí que está o maior valor:

```yaml
apt:
  required:
    ros-humble-ros-gzgarden-image: "0.244.*"
  forbidden:
    ros-humble-ros-gz-image: >-
      Variante FORTRESS do bridge. Com Gazebo Garden instalado ela roda mas
      NÃO enxerga nenhum tópico do Gazebo — sem mensagem de erro.
```

Um pacote que instala limpo e quebra em silêncio não é detectável por nenhuma
ferramenta automática. Alguém precisa ter descoberto e escrito ali.

> **Regra:** toda versão que já quebrou o time vira uma linha num perfil. Um
> diagnóstico que não virou checagem vai ser refeito do zero daqui a alguns meses.

---

## 4. Perfis de plataforma

O time voa com **duas plataformas ao mesmo tempo**. Numa mesma competição (a CBR,
por exemplo), as fases 1–3 podem ser do drone com Jetson e a fase 4 do drone com
Raspberry Pi.

| Perfil | Máquina | Distro / Ubuntu | Simulação | Existe? |
|---|---|---|---|---|
| `desktop-humble` | PC de desenvolvimento | Humble / 22.04 | sim (PX4 SITL + Gazebo Garden) | **sim** |
| `jetson-humble` | Jetson Orin Nano | Humble / 22.04 | não | ainda não |
| `rpi-jazzy` | Raspberry Pi | Jazzy / 24.04 | não | ainda não |

Os dois últimos precisam ser levantados **nas máquinas reais** — veja o
[Passo 8](#passo-8--se-a-competição-usa-a-raspberry). Rode `./doctor.sh --list`
para ver o que existe hoje.

Cada máquina escolhe o seu **uma vez**, e o registro fica em `.evtol-profile` na
raiz — arquivo local, não versionado, porque cada máquina tem o seu.

```bash
./doctor.sh --list                      # ver os disponíveis
./setup.sh --profile desktop-humble     # escolher (grava .evtol-profile)
./doctor.sh                             # depois disso, sem argumento
```

**Não existe perfil padrão, de propósito.** Adivinhar errado é justamente o bug
que isso veio eliminar.

### A regra que decorre disso

**Nunca escreva `source /opt/ros/humble/setup.bash` num script.** Use:

```bash
source scripts/ros_env.sh
```

Esse script lê o perfil, descobre a distro e carrega o ROS certo mais o
`install/` do workspace. O mesmo comando funciona no seu PC, na Jetson e na
Raspberry. É o que permite um script só servir às três.

---

## 5. Os scripts

### Na raiz — genéricos, servem a qualquer competição

| Script | O que faz |
|---|---|
| `setup.sh` | Bootstrap completo: verifica ambiente → importa repos → rosdep → compila |
| `doctor.sh` | Compara a máquina com o perfil e falha alto, com a correção pronta |
| `scripts/ros_env.sh` | Carrega o ROS da distro do perfil + o `install/`. **Use sempre este.** |
| `scripts/image_bridge.sh` | Ponte de imagem Gazebo → ROS (`ros_gz_image`) |
| `scripts/ground_station.sh` | Sobe a estação de solo de uma missão |
| `scripts/garra.py`, `fechar_garra.sh`, ... | Controle do servo da garra (GPIO da Jetson) |

#### `setup.sh` — a ordem importa

```
1. doctor.sh          ← PORTÃO: para aqui se o ambiente não confere
2. vcs import         ← traz os repos nas versões pinadas
3. rosdep install     ← dependências de sistema
4. colcon build
```

O passo 1 vem primeiro de propósito. Compilar num ambiente errado não gera um
erro que aponta para a causa: gera comportamento estranho horas depois. É mais
barato falhar no início, com a linha de correção na tela.

Existe `--skip-doctor`, mas ele **não serve para "resolver" uma reprovação**. A
reprovação é real.

#### `doctor.sh` — o que ele confere

Sistema operacional e Python · distro do ROS (instalada **e** ativa no shell) ·
pacotes apt obrigatórios e proibidos · pacotes pip obrigatórios e proibidos ·
binários no PATH (`gz`, `MicroXRCEAgent`, `colcon`, `vcs`, `rosdep`) ·
**um teste funcional** que instala um pacote `ament_python` de mentira e confirma
que o caminho do `colcon build --symlink-install` funciona ·
repositórios externos (`PX4-Autopilot`, `Micro-XRCE-DDS-Agent`,
`PX4-gazebo-models`) na versão certa · e o **contrato de API do OpenCV**.

Sai com código 0 ou 1, então serve de portão no `setup.sh` e no CI.

O contrato de API é a rede de segurança final: ele varre o código em `src/` com
AST, extrai todo símbolo `cv2.X` que o código chama, e confere que existe no
OpenCV instalado. Pega a classe de bug em que a versão muda e uma função some —
mesmo quando as versões divergem entre plataformas por motivo legítimo. Ele
entende as guardas de compatibilidade (`hasattr`, `try/except AttributeError`) e
só varre os repositórios declarados no `evtol.repos`.

### Em cada competição — `src/<competição>/scripts/`

Cada competição tem os seus, copiados de `templates/scripts/`:

| Script | Customização necessária |
|---|---|
| `simulate.sh` | **Sim.** Preencha o `case` com os mundos, modelos e poses. |
| `build.sh` | Normalmente não. Aceita `deps`, `all` ou qualquer pacote da competição. |
| `agent.sh` | Só se for voar com serial em vez de simulação. |

Por que cada competição tem os seus, em vez de um script central: os mundos, os
modelos e as poses iniciais são da competição. Um `simulate.sh` central viraria
um `case` gigante com todos os anos misturados.

---

## 6. O CI

Todo repositório de biblioteca tem `.github/workflows/build.yml`. **O arquivo é
idêntico em todos** — os pacotes são descobertos com `colcon list`, então serve
tanto para um repositório de um pacote quanto para o `cv_nodes`, que tem doze.

| Job | Bloqueia merge? | O que faz |
|---|---|---|
| `build (humble)` | **sim** | Compila na imagem `ros:humble-ros-base` |
| `build (jazzy)` | **sim** | Compila na imagem `ros:jazzy-ros-base` |
| `lint (informativo)` | não | Roda os linters do ament |

### Por que a matriz de dois distros

É a única garantia real de que uma biblioteca compartilhada não virou
Humble-only sem ninguém perceber. Sem isso, o problema só aparece quando alguém
tenta usá-la na Raspberry — normalmente no pior momento possível.

### Por que as imagens são mínimas (`-ros-base`, não `-desktop`)

Porque é assim que uma Jetson ou Raspberry recém-instalada se parece. Na máquina
de desenvolvimento o `ros-humble-desktop` traz dezenas de pacotes de carona, e
uma dependência não declarada simplesmente funciona. No primeiro dia, o CI
encontrou quatro casos assim:

- `drone_lib` exigia `cv_bridge` no CMake sem declarar no `package.xml` — e sem
  usar em lugar nenhum do código.
- `drone_lib` e `stdstates` declaravam `<depend>Eigen3</depend>`; `Eigen3` é
  nome de pacote **CMake**, a chave do **rosdep** é `eigen`.
- `telemetry_handler` declarava `python3-tkinter`; a chave é `python3-tk`.
- `camera_publisher` declarava `opencv-python` e `depthai`, que não existem no
  índice do rosdep.

### De onde o CI tira as versões

Do `evtol.repos` da `main` do `evtol-dev` — não de uma lista duplicada em cada
repositório. Assim o CI responde à pergunta certa: *"este repositório funciona
com o workspace que o time realmente usa?"*. A própria entrada do repositório é
removida do manifesto antes do import, para testar o código do PR e não o da tag
pinada.

Isso tem um efeito que já se provou útil: quando o `stdstates` reprovou, a causa
não estava nele — estava na versão do `drone_lib` que o manifesto pinava. O CI
mostra a propagação.

### Por que o lint não bloqueia

Esses pacotes não têm teste unitário; o `colcon test` roda só os linters do
ament, e alguns reprovam num código que nunca teve lint. Ligar isso como
obrigatório de uma vez produziria uma parede de ruído e ensinaria o time a
ignorar o CI — que é o oposto do objetivo. Fica visível; quando o estilo for
acertado num PR próprio, promove-se.

---

## 7. Rotina do dia a dia

```bash
cd ~/evtol/dev
source scripts/ros_env.sh          # em todo shell novo
```

**Simulação (três terminais):**

```bash
# T1 — PX4 + Gazebo
bash src/sae2026/scripts/simulate.sh sae1

# T2 — ponte PX4 <-> ROS 2
bash src/sae2026/scripts/agent.sh

# T3 — a missão
source scripts/ros_env.sh
ros2 launch mission_1 simulation.launch.py
```

Ou, no VSCode: `Ctrl+Shift+P` → *Tasks: Run Task* → **simulation start**.

**Compilar:**

```bash
bash src/sae2026/scripts/build.sh mission_1   # uma missão e o que ela precisa
bash src/sae2026/scripts/build.sh deps        # só as bibliotecas compartilhadas
```

**Antes de voar, ou quando algo estiver estranho:**

```bash
./doctor.sh
```

### Quando alguém bumpa um pin

```bash
git pull                        # traz o evtol.repos novo
vcs import src < evtol.repos    # atualiza os repositórios em src/
./doctor.sh
bash src/sae2026/scripts/build.sh all
```

### ⚠️ `vcs import` deixa os repositórios em *detached HEAD*

Isto confunde todo mundo na primeira vez, então leia com atenção.

O `evtol.repos` pina **tags**, e uma tag não é um branch. Depois de um
`vcs import`, cada repositório em `src/` fica assim:

```bash
$ git -C src/drone_lib status
HEAD detached at v0.2.0
```

Nesse estado você **pode compilar e rodar normalmente**, mas **não deve
commitar**: um commit em detached HEAD não pertence a branch nenhum e some do
seu radar assim que você trocar de lugar.

**A regra prática:**

| Situação | O que fazer |
|---|---|
| Montar a máquina, reproduzir o que voou, rodar o CI | `vcs import` — detached é o certo |
| Ir mexer no código de um repositório | `git checkout main` **naquele repositório**, e trabalhe a partir dali |

```bash
cd ~/evtol/dev/src/drone_lib
git checkout main               # sai do detached
git pull
git checkout -b fix/meu-ajuste  # e então trabalhe
```

Se você já commitou em detached HEAD sem querer, nada se perdeu — basta criar
um branch ali mesmo, antes de sair:

```bash
git branch -c recupera-meu-trabalho   # ou: git switch -c recupera-meu-trabalho
```

**Antes de rodar `vcs import`,** confira se algum repositório tem trabalho
pendente, porque ele vai trocar o que está checado out:

```bash
cd ~/evtol/dev
for d in src/*/; do
    printf '%-24s %s\n' "$(basename "$d")" \
      "$(git -C "$d" status --porcelain 2>/dev/null | wc -l) alterações"
done
```

---

## 8. Começando uma competição nova, do zero

Cenário: a equipe vai participar da **CBR 2027** e você vai montar o software.

### Passo 0 — Máquina pronta

Se for uma máquina nova, siga [SETUP.md](SETUP.md) primeiro (ROS, PX4,
Micro-XRCE-DDS-Agent, Gazebo). Depois:

```bash
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git ~/evtol/dev
cd ~/evtol/dev
./setup.sh --profile desktop-humble
```

Ao final, `./doctor.sh` tem que passar. **Não siga adiante com o doctor
reprovando** — cada item dele já custou tempo ao time.

---

### Passo 1 — Criar o repositório da competição

No GitHub da organização, crie `cbr2027` (público, sem README — vamos preencher).
Depois:

```bash
cd ~/evtol/dev/src
git clone https://github.com/Equipe-eVTOL-ITA/cbr2027.git
cd cbr2027
```

> **Por que um repositório novo por competição, e não uma pasta no anterior:**
> competições são descartáveis e paralelas. Você quer poder congelar o que voou
> na CBR 2027 sem que isso trave o desenvolvimento do ano seguinte.

---

### Passo 2 — Copiar os scripts

```bash
mkdir -p ~/evtol/dev/src/cbr2027/scripts
cp ~/evtol/dev/templates/scripts/*.sh ~/evtol/dev/src/cbr2027/scripts/
chmod +x ~/evtol/dev/src/cbr2027/scripts/*.sh
```

Agora **customize o `simulate.sh`** — é o único que exige. Abra e preencha o
bloco `case` com os mundos da competição:

```bash
case "${1:-}" in
    fase1)
        PX4_GZ_WORLD=cbr1_27                                 # nome do .sdf
        PX4_GZ_MODEL_POSE="0.0, 0.0, 0.05, 0.0, 0.0, 0.0"    # x,y,z,roll,pitch,yaw
        PX4_SIM_MODEL=x500_sae                               # modelo do drone
        ;;
    fase4)
        PX4_GZ_WORLD=cbr4_27
        PX4_GZ_MODEL_POSE="2.0, -1.0, 0.05, 0.0, 0.0, 1.57"
        PX4_SIM_MODEL=x500_dual_cam
        ;;
    ...
```

Os mundos (`.sdf`) e modelos vivem no repositório
[PX4-gazebo-models](https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models). Basta
cloná-lo em `~` — modelos são achados pelo `GZ_SIM_RESOURCE_PATH` e o
`simulate.sh` linka sozinho o mundo que for lançar. Se a competição tem arena
nova, é lá que o `.sdf` entra. Veja
[gazebo_models_setup.md](gazebo_models_setup.md).

O `build.sh` e o `agent.sh` normalmente não precisam de mudança.

---

### Passo 3 — Criar o primeiro pacote de missão

Toda fase de competição tem a mesma estrutura inicial: os mesmos includes, uma
classe que herda de `fsm::FSM`, outra que herda de `rclcpp::Node`, o carregamento
dos parâmetros na blackboard, os estados de arming/takeoff/landing com suas
transições, o timer de 20 Hz e o `main` com o executor.

**Não escreva isso à mão.** Um comando gera tudo:

```bash
cd ~/evtol/dev/src/cbr2027
~/evtol/dev/templates/new_mission.sh fase1
```

O que sai:

```
fase1/
├── package.xml                    dependências já declaradas
├── CMakeLists.txt                 alvo, includes, install de launch/ e config/
├── src/fase1.cpp                  FSM + Node completos
├── include/fase1/states/
│   └── example_state.hpp          estado de exemplo, comentado, para copiar
├── config/simulation.yaml
├── config/flight.yaml
└── launch/simulation.launch.py
    launch/flight.launch.py
```

**O pacote gerado já compila e já voa** — arma, decola e pousa — sem você
escrever uma linha. É o esqueleto mínimo funcional, para você começar pela
lógica da missão em vez de pelo boilerplate.

Dentro do `.cpp` os pontos de extensão estão marcados com **`ACRESCENTE`**:

| Onde | O que colocar |
|---|---|
| `// ACRESCENTE aqui os estados` | `add_state("MEU_ESTADO", ...)` |
| bloco de transições do `TAKEOFF` | trocar `LANDING` pelo primeiro estado real da missão |
| `default_params` | os parâmetros da sua missão (e replicar nos dois YAML) |
| assinatura de visão | o `create_subscription` do detector que a fase usa |

#### Criando um estado

Copie o modelo e ajuste:

```bash
cp fase1/include/fase1/states/example_state.hpp \
   fase1/include/fase1/states/search_target_state.hpp
```

Um estado tem três partes:

| Método | Quando roda | Para quê |
|---|---|---|
| `on_enter` | uma vez, ao entrar | ler parâmetros da blackboard, guardar o alvo |
| `act` | a cada tick (20 Hz) | a lógica; devolve `""` para ficar, ou um outcome para transitar |
| `on_exit` | uma vez, ao sair | limpeza (opcional) |

Depois é só incluir o header no `.cpp`, registrar com `add_state` e ligar as
transições.

> **Tudo compartilhado passa pela blackboard.** Nunca variável global, nunca
> ponteiro passado entre estados. O nó de visão escreve na blackboard pelo
> callback; os estados só leem.

> **Configuração, não código.** Trocar de simulação para voo real é trocar de
> YAML, não editar `.cpp`. E variação de missão (busca em H em vez de linear)
> deve ser parâmetro — não um pacote duplicado. O `sae2026` tem `mission_1` e
> `mission_1_H`, que é exatamente o erro a não repetir.

<details>
<summary>Se preferir criar o pacote à mão</summary>

Use `ros2 pkg create` — não escreva o `CMakeLists.txt` do zero:

```bash
ros2 pkg create --build-type ament_cmake --license MIT \
  --dependencies rclcpp fsm drone_lib stdstates custom_msgs \
  --node-name fase1 fase1
mkdir -p fase1/config fase1/launch fase1/include/fase1/states
```

Dois detalhes que costumam custar tempo:

- O `maintainer` do `package.xml` precisa de um e-mail **válido**. Um
  placeholder como `a@b.c` faz o build falhar com um erro de parse que não
  explica a causa. (O gerador pega do seu `git config user.email`.)
- No `main`, **não** adicione o `Drone` ao executor. Ele já sobe o próprio
  executor e a própria thread de spin no construtor; adicioná-lo lança
  `Node '/Drone' has already been added to an executor` em tempo de execução.

</details>

---

### Passo 4 — Compilar e rodar

```bash
cd ~/evtol/dev
bash src/cbr2027/scripts/build.sh fase1
```

Abra um **terminal novo** e:

```bash
cd ~/evtol/dev
source scripts/ros_env.sh
ros2 run fase1 fase1
```

Terminal novo importa: o `install/setup.bash` precisa ser recarregado para o
pacote novo aparecer.

Simulação completa, três terminais:

```bash
bash src/cbr2027/scripts/simulate.sh fase1     # T1
bash src/cbr2027/scripts/agent.sh              # T2
source scripts/ros_env.sh && ros2 run fase1 fase1   # T3
```

---

### Passo 5 — Publicar e versionar

```bash
cd ~/evtol/dev/src/cbr2027
git add -A
git commit -m "feat: estrutura inicial da CBR 2027 (scripts + fase1)"
git push
```

Quando a competição estiver num estado estável, crie uma tag e adicione ao
manifesto — assim qualquer pessoa monta o workspace da competição com um comando:

```bash
git tag -a v0.1.0 -m "Primeira versão da CBR 2027"
git push origin v0.1.0
```

E, num PR ao `evtol-dev`, acrescente ao `evtol.repos`:

```yaml
  cbr2027:
    type: git
    url: https://github.com/Equipe-eVTOL-ITA/cbr2027.git
    version: v0.1.0
```

---

### Passo 6 — CI no repositório novo

```bash
mkdir -p ~/evtol/dev/src/cbr2027/.github/workflows
cp ~/evtol/dev/templates/workflows/build.yml \
   ~/evtol/dev/src/cbr2027/.github/workflows/
```

**O arquivo não precisa de nenhuma edição** — os pacotes são descobertos
sozinhos. Commite, e o CI passa a compilar a competição em Humble e Jazzy a cada
PR.

Depois, em *Settings → Branches* do repositório, ative **"Require status checks
to pass before merging"** para `build (humble)` e `build (jazzy)`.

---

### Passo 7 — Quando faltar uma capacidade

Se a fase precisa de algo que o workspace ainda não tem, a pergunta é **onde
isso mora**:

| A capacidade é... | Vai para |
|---|---|
| Específica desta competição (a lógica da fase 3 de 2027) | `cbr2027/fase3/` |
| Um estado reutilizável (alinhar com um alvo, orbitar) | `stdstates` |
| Um detector novo (achar um código de barras) | `cv_nodes` |
| Um tipo de mensagem novo | `custom_msgs` |
| Uma capacidade do veículo (novo modo de controle) | `drone_lib` |

Ao mexer numa biblioteca compartilhada: PR no repositório dela → CI verde →
merge → **tag nova** → PR no `evtol-dev` atualizando o `evtol.repos`. É esse
último passo que faz a mudança chegar às outras máquinas de forma controlada.

> Se o repositório da competição está ficando grande, quase sempre é sinal de
> que alguma capacidade genérica está no lugar errado.

---

### Passo 8 — Se a competição usa a Raspberry

Cada máquina roda o seu próprio `setup.sh` com o seu perfil:

```bash
# na Raspberry
git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git ~/evtol/dev
cd ~/evtol/dev && ./setup.sh --profile rpi-jazzy
```

Se o perfil ainda não existir, rode o levantamento **na máquina** e traga o
arquivo para revisão:

```bash
./env/collect.sh > /tmp/perfil.yaml
```

Ele coleta distro, versões de apt e pip, binários e repositórios externos, e
detecta a plataforma (L4T/CUDA na Jetson, `libcamera` na Raspberry). O resultado
é um **rascunho**: alguém precisa decidir quais valores viram contrato e
preencher a lista de `forbidden`, que nenhuma ferramenta consegue inferir.

---

## 9. Quando algo dá errado

**Primeiro comando, sempre:**

```bash
cd ~/evtol/dev && ./doctor.sh
```

| Sintoma | Causa provável |
|---|---|
| Nenhum tópico do Gazebo no ROS | Variante errada do bridge. O doctor pega. |
| Nó de visão morre no primeiro frame | Versão de OpenCV / API do ArUco. O contrato de API pega. |
| `error: option --editable not recognized` | `setuptools >= 80`. O doctor pega. |
| `canonicalize_version() got an unexpected keyword argument` | `packaging` velho (21.3 do apt) com `setuptools >= 71`. `pip install --user 'packaging>=23'`. O doctor pega. |
| `SystemError` no `imgmsg_to_cv2` | `numpy >= 2` com o `cv_bridge` do Humble. O doctor pega. |
| Pacote compila mas o `ros2 run` não acha | Terminal antigo. Abra outro e `source scripts/ros_env.sh`. |
| `git commit` some / "HEAD detached at v0.2.0" | Normal depois de `vcs import`. Veja [a seção sobre isso](#vcs-import-deixa-os-repositórios-em-detached-head). |
| Build falha só na sua máquina | Rode `./doctor.sh`; se passar, pode ser dependência não declarada — o CI mostra. |
| Máquina trava durante o build | Falta de RAM. Veja a seção de swap no [SETUP.md](SETUP.md). |
| `gz_bridge: Service call timed out. Check GZ_SIM_RESOURCE_PATH` | Quase sempre **não** é o path. Ou o `.sdf` não existe em `~/PX4-gazebo-models` (o `simulate.sh` avisa antes), ou o Gazebo demorou demais no primeiro arranque numa máquina com pouca RAM — tente de novo. |
| Um pacote fica num estado esquisito | `rm -rf build/<pkg> install/<pkg>` e recompile. |
| `Node '/Drone' has already been added to an executor` | O `Drone` já sobe o próprio executor. Remova o `executor.add_node(drone)` do `main` — só o nó da missão entra. |

### Onde perguntar ao próprio workspace

```bash
colcon list --names-only                    # todos os pacotes
colcon graph --packages-up-to <pkg>         # o que ele precisa
ros2 pkg executables <pkg>                  # o que dá para rodar
ros2 topic list                             # o que está publicando agora
./doctor.sh --list                          # perfis disponíveis
```

---

## Em uma frase

O `evtol.repos` garante que todo mundo tem o mesmo **código**; o
`env/<perfil>.yaml` garante que todo mundo tem o mesmo **ambiente**; o **CI**
garante que os dois continuam verdadeiros amanhã. O resto é software de drone.
