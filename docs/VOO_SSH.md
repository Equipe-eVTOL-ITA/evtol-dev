# Rodar uma missão na Jetson, pelo SSH

Como voar a partir do seu computador, com a Jetson embarcada no drone.

> **A Jetson não tem tela.** Tudo aqui acontece por SSH, e a diferença que mais
> importa é esta: **se a conexão cair, o processo morre junto** — a menos que ele
> esteja dentro de um `tmux`. Com o drone no ar, isso não é um detalhe de
> conforto.

---

## Antes de ir para o campo

### 1. A Jetson precisa saber quem ela é

Uma vez, na Jetson:

```bash
cd ~/evtol/dev
echo jetson-humble > .evtol-profile
./doctor.sh
```

O `doctor` compara a máquina com o perfil e **para o trabalho se algo não bate**.
Na primeira vez ele vai reclamar: o perfil `jetson-humble` foi escrito sem ver a
máquina real, e diz isso no próprio arquivo. Cada reclamação é uma coisa a
instalar — ou, se o perfil é que está errado, a corrigir **no perfil**, para a
próxima Jetson não repetir a descoberta.

### 2. Compilar

```bash
bash src/cbr2026/scripts/build.sh all
```

`deps` compila só as bibliotecas compartilhadas, e é o que você usa depois de
mexer numa fase.

### 3. Três valores do `flight.yaml` que ninguém pode adivinhar

Em `src/cbr2026/fase1/config/flight.yaml`:

| chave | por quê |
|---|---|
| `camera_fx/fy/cx/cy` | estão em **`0.0`**, o que faz o código cair no FOV nominal. Meça com o `camera_calibrator`. Uma lente real tem distorção e centro deslocado, e o erro cresce para as bordas — justamente onde a base aparece na aproximação. |
| faixas HSV | na iluminação **do dia**. Lona sob sol não tem cor uniforme. |
| `fictual_home_x/y/z` | o ponto de decolagem real na arena. |

---

## A rede

O seu computador e a Jetson precisam **se enxergar** e estar no **mesmo
`ROS_DOMAIN_ID`**. É isso que faz `ros2 topic list` no seu PC mostrar os tópicos
que nascem no drone.

```bash
# no seu computador
export ROS_DOMAIN_ID=0        # o mesmo que estiver na Jetson
ros2 topic list               # tem de listar os /fmu/... do drone
```

Se a lista vier vazia com tudo rodando, é rede — não é a missão. Cheque se as
duas máquinas estão na mesma sub-rede e sem firewall no meio.

---

## Voando

### Conecte com `tmux`, não com um SSH pelado

```bash
ssh jetson@<ip-da-jetson>
tmux new -s voo
```

**Por que isso importa:** sem o `tmux`, fechar o terminal, perder o Wi-Fi ou
tropeçar no cabo mata a missão **no meio do voo**. Com ele, a sessão continua na
Jetson e você reconecta:

```bash
ssh jetson@<ip-da-jetson>
tmux attach -t voo
```

Atalhos que bastam: `Ctrl+b c` abre uma janela, `Ctrl+b n` alterna, `Ctrl+b d`
desconecta **deixando tudo rodando**.

### Janela 1 — o agente DDS, ligado ao Pixhawk por serial

```bash
cd ~/evtol/dev
source scripts/ros_env.sh
MicroXRCEAgent serial --dev /dev/ttyTHS1 -b 921600
```

> Em simulação o agente fala UDP na porta 8888. **Em voo é serial** — o Pixhawk
> está ligado por fio, não por rede. O `scripts/agent.sh` ainda só cobre o caso
> UDP; por isso o comando aqui é direto.
>
> Confirme o dispositivo: na Jetson costuma ser `/dev/ttyTHS1`, mas depende de
> como o Pixhawk foi ligado. `ls /dev/tty*` com e sem o cabo mostra qual é.

### Janela 2 — a missão

```bash
cd ~/evtol/dev
source scripts/ros_env.sh
ros2 launch fase1 flight.launch.py
```

Isso sobe, nesta ordem: a câmera, o detector de bases, o `system_health`, um
**rosbag**, e — cinco segundos depois — a missão. O atraso existe para a FSM não
decolar antes de o detector estar pronto e varrer o primeiro trecho da grade
cega.

### Janela 3 — olhar de fora, do seu computador

Não precisa de SSH: com o mesmo `ROS_DOMAIN_ID`, os tópicos chegam.

```bash
ros2 topic echo /telemetry/drone_status
ros2 topic hz   /vertical_camera/compressed     # a câmera está entregando?
ros2 topic echo /base_detector/detections       # o detector está vendo?
```

---

## O que olhar quando algo não funciona

**O drone não arma.** Olhe a janela do agente. Se ela não mostra tópicos sendo
criados, o Pixhawk não está falando — dispositivo ou baud errados.

**A missão decola e não vê base nenhuma.** Rode `ros2 topic hz` no tópico da
câmera. Se ele não publica, o problema é a câmera; se publica e o detector não
acha nada, são as faixas HSV.

> **O defeito que já custou duas fases a este time:** o tópico da câmera não
> casar com o que o detector assina. O detector **sobe, não reclama e nunca
> recebe quadro** — a missão voa cega e o log não diz por quê.
>
> Hoje a convenção é uma só, e vale para as quatro câmeras:
> **`<papel>_camera/compressed`**, sem `/image/` no meio. `<papel>` é
> `vertical`, `frontal` ou `horizontal` — a posição no drone, **não** o modelo
> do hardware. Trocar uma webcam por uma Raspberry Pi Camera na mesma posição
> não muda o tópico.
>
> Se você mexer nisso, o comando que resolve a dúvida em cinco segundos é
> `ros2 topic list | grep camera`.

**A conexão caiu.** Reconecte e `tmux attach -t voo`. Se você **não** estava no
`tmux`, a missão morreu junto — e é por isso que ele está aqui.

---

## Depois do voo

Cada voo grava um bag em `~/evtol/mission_logs/fase1_<data>/` **na Jetson**.
Traga-o para o seu computador antes que ele se perca:

```bash
# do seu computador
rsync -avz jetson@<ip>:~/evtol/mission_logs/ ~/evtol/mission_logs/
```

Depois de uma missão que deu errado, esse bag é a única forma de saber o que o
drone via no momento.

---

## O que ainda não está pronto

Três coisas que você vai encontrar, e é melhor saber antes do que no campo:

**O perfil `jetson-humble` nunca foi validado na máquina real.** Ele declara só o
que dá para afirmar sem ver a Jetson, e diz isso no próprio arquivo. O primeiro
`./doctor.sh` lá é o teste de verdade.

**A task `voo: ground station` está quebrada.** Ela chama
`ros2 launch <pacote> ground_station.launch.py`, e **nenhuma fase tem esse
arquivo**. Ela falha em qualquer fase.

**A fase 1 não foi revalidada desde o `stdstates` v0.3.0**, que mudou o pouso
para *medir* a altitude de partida em vez de lê-la do YAML. Ela voou antes disso.
Vale uma passada em SITL antes da arena.
