# Como fazer uma FSM

**Para quem acabou de entrar na equipe.** Ao final deste documento você vai ter
escrito, compilado e rodado uma máquina de estados que **arma, decola, paira
três segundos e pousa** — com um estado escrito por você.

Não é preciso saber ROS 2 a fundo, nem C++ avançado. É preciso ter o workspace
funcionando: [SETUP.md](SETUP.md) para a máquina, [GUIA.md](GUIA.md) para o
workspace.

> **Já sabe FSM e quer saber quando usar Behavior Tree?** Pule para a seção
> [10](#10-fsm-ou-bt) e depois para [BT.md](BT.md). Os dois motores convivem no
> mesmo workspace e **compartilham os mesmos estados**.

> Os links para `src/...` apontam para os repositórios que o `vcs import` traz —
> eles abrem no VS Code, não no GitHub deste repositório, porque `src/` é
> gitignorado aqui (ver [GUIA.md](GUIA.md#por-que-src-é-gitignorado)).

---

## Índice

1. [O modelo mental](#1-o-modelo-mental)
2. [Onde cada coisa mora](#2-onde-cada-coisa-mora)
3. [Gere o pacote — não escreva boilerplate](#3-gere-o-pacote--não-escreva-boilerplate)
4. [Anatomia do arquivo gerado](#4-anatomia-do-arquivo-gerado)
5. [Exercício: acrescente o estado HOVER](#5-exercício-acrescente-o-estado-hover)
6. [Estados que você não precisa escrever](#6-estados-que-você-não-precisa-escrever)
7. [As regras da casa](#7-as-regras-da-casa)
8. [Checklist antes de voar](#8-checklist-antes-de-voar)
9. [Quando não funciona](#9-quando-não-funciona)
10. [FSM ou BT?](#10-fsm-ou-bt)

---

## 1. O modelo mental

Uma FSM (*finite state machine*, máquina de estados finita) modela a missão como
um **grafo**: cada nó é uma coisa que o drone está fazendo, cada aresta é o
motivo de parar de fazê-la e começar outra. Um estado ativo por vez, sempre.

```
ARMING ──"ARMED"──▶ TAKEOFF ──"TAKEOFF COMPLETED"──▶ LANDING ──"LANDED"──▶ FINISHED
   │                    │                               │
   └──"ERROR"───────────┴───────────────────────────────┴──────────────▶ ERROR
```

Essas strings entre aspas são os **outcomes**. Quem produz um outcome é o
estado; quem decide para onde ele leva é a FSM, na montagem.

### O ciclo de um tick

O nó ROS da missão tem um timer de **50 ms (20 Hz)**. A cada disparo ele chama
`fsm_->execute()`, e o `execute()` faz exatamente duas coisas
([fsm.cpp](../src/fsm/fsm/src/fsm/fsm.cpp)):

```
execute()
  ├── outcome = estado_atual->act(blackboard)
  └── se outcome != ""  →  estado_atual->on_exit()
                           estado_atual = transições[outcome]
                           estado_novo->on_enter()
```

Ou seja: **um `act` por tick, 20 vezes por segundo.** Um estado não "roda até
terminar" — ele é chamado repetidamente e precisa se lembrar de onde parou
usando os próprios membros.

| Método | Quando roda | Para quê |
|---|---|---|
| `on_enter(bb)` | uma vez, ao entrar | ler parâmetros da blackboard, guardar a posição de partida, calcular o alvo |
| `act(bb)` | a cada tick (20 Hz) | agir; devolver `""` para ficar no estado, ou um outcome para sair |
| `on_exit(bb)` | uma vez, ao sair | limpar — na prática, **zerar a velocidade comandada** |

Dois detalhes que economizam meia hora de confusão:

- **O primeiro tick não chama o seu `act`.** A FSM começa num estado interno
  `INITIAL`, cujo único trabalho é transitar para o estado inicial de verdade —
  e essa transição dispara o `on_enter`. Seu `act` roda a partir do tick
  seguinte, 50 ms depois. Estados que leem a pose no `on_enter` e agem no `act`
  contam com esse intervalo.
- **Devolver `""` é a coisa normal.** Um estado que devolve outcome em todo tick
  provavelmente não deveria ser um estado.

### A blackboard

É o único canal de dados da missão: um mapa `string → valor` que a FSM carrega e
passa para todo estado.

```cpp
// escrevendo, de dentro de um estado
blackboard.set<float>("hover_time", 3.0f);

// escrevendo na montagem da FSM (a classe fsm::FSM expõe este atalho)
this->blackboard_set<float>("hover_time", 3.0f);

// lendo
float *p = blackboard.get<float>("hover_time");   // PONTEIRO, nullptr se faltar
```

Três coisas sobre ela, todas com consequência prática:

1. **`get` devolve `nullptr` quando a chave não existe.** O idioma
   `*blackboard.get<float>("x")` — que você vai ver em vários estados antigos —
   é um segfault se alguém errar o nome no YAML. Use
   [`stdstates::require`](../src/stdstates/include/stdstates/blackboard_params.hpp).
2. **O tipo faz parte do contrato.** O `get<T>` faz um cast C **sem checagem**:
   gravar `double` e ler `float` compila, roda e devolve lixo. Todo o
   `stdstates` lê `float`.
3. **Tudo compartilhado passa por ela.** Nunca variável global, nunca ponteiro
   de um estado para outro. O nó de visão escreve na callback; os estados só
   leem.

### Como a missão termina

A FSM é construída com o conjunto de **outcomes terminais**:

```cpp
fsm::FSM({"ERROR", "FINISHED"})
```

Quando o estado atual passa a ser um desses nomes, `is_finished()` vira `true` e
o nó desliga. `"FINISHED"` e `"ERROR"` não são estados — são fins de linha.

---

## 2. Onde cada coisa mora

| Pacote | O que é | Você mexe? |
|---|---|---|
| [`fsm`](../src/fsm) | o motor: `fsm::FSM`, `fsm::State`, `fsm::Blackboard` | não |
| [`stdstates`](../src/stdstates) | os 11 estados genéricos, já validados em voo | raramente — só se o estado for genérico de verdade |
| [`drone_lib`](../src/drone_lib) | a classe `Drone`: pose, setpoints, armar, logar | não |
| `src/<competição>/<fase>/` | **a sua missão**: estados próprios, parâmetros, launch | sim, sempre |

A regra por trás dessa tabela está em [ARCHITECTURE.md](ARCHITECTURE.md): lógica
que serve a mais de uma prova sobe para a biblioteca; regra de negócio da prova
fica na fase. O `stdstates` nasceu de nove cópias divergentes do mesmo
`PidController`.

---

## 3. Gere o pacote — não escreva boilerplate

Toda fase começa igual: os mesmos includes, uma classe que herda de `fsm::FSM`,
outra que herda de `rclcpp::Node`, os parâmetros indo para a blackboard, o timer
de 20 Hz, o `main` com o executor. **Não escreva isso à mão** — há três
armadilhas conhecidas nesse boilerplate (e-mail do maintainer, chave do rosdep
do Eigen, `Drone` no executor) e o gerador já acerta as três.

```bash
cd ~/evtol/dev/src/cbr2026          # de dentro do repo da competição
~/evtol/dev/templates/new_mission.sh fase_treino
```

O que sai:

```
fase_treino/
├── package.xml                     dependências declaradas
├── CMakeLists.txt                  alvo, includes, install de launch/ e config/
├── src/fase_treino.cpp             FSM + Node: ARMING → TAKEOFF → LANDING
├── include/fase_treino/states/
│   └── example_state.hpp           estado de exemplo, comentado, para copiar
├── config/simulation.yaml          parâmetros da simulação
├── config/flight.yaml              parâmetros do voo real
└── launch/{simulation,flight}.launch.py
```

**O pacote gerado já compila e já voa** — arma, decola, pousa — sem você
escrever uma linha. Compile e veja:

```bash
cd ~/evtol/dev
bash src/cbr2026/scripts/build.sh fase_treino
```

Para rodar, três terminais (ou as tasks do VS Code — `Ctrl+Shift+P` →
*Tasks: Run Task* → **sim: iniciar com missão**, que faz os três de uma vez):

```bash
bash src/cbr2026/scripts/simulate.sh <mundo>     # T1: PX4 + Gazebo
bash src/cbr2026/scripts/agent.sh                # T2: ponte PX4 ↔ ROS 2
source scripts/ros_env.sh                        # T3: a missão
ros2 launch fase_treino simulation.launch.py
```

> Se o nome da fase não aparecer nas listas suspensas das tasks, rode
> `python3 scripts/sync_tasks.py`. O `new_mission.sh` já faz isso ao gerar.

---

## 4. Anatomia do arquivo gerado

Abra `src/fase_treino.cpp`. São duas classes, e os pontos de extensão estão
marcados com **`ACRESCENTE`**.

### 4.1 A FSM

```cpp
class FaseTreinoFSM : public fsm::FSM {
public:
    FaseTreinoFSM(std::shared_ptr<Drone> drone,
                  const std::map<std::string, std::variant<double, std::string>> &params)
      : fsm::FSM({"ERROR", "FINISHED"})           // ① outcomes terminais
    {
        this->blackboard_set<std::shared_ptr<Drone>>("drone", drone);   // ②

        for (const auto &[key, value] : params) {                      // ③
            if (std::holds_alternative<double>(value))
                this->blackboard_set<float>(key, static_cast<float>(std::get<double>(value)));
            ...
        }

        this->add_state("ARMING",  std::make_unique<ArmingState>());    // ④
        this->add_state("TAKEOFF", std::make_unique<TakeoffState>());
        this->add_state("LANDING", std::make_unique<LandingState>());

        this->add_transitions("ARMING", {                               // ⑤
            {"ARMED", "TAKEOFF"},
            {"ERROR", "ERROR"}
        });
        ...
        this->set_initial_state("ARMING");                              // ⑥
    }
};
```

| | O que é, e por que importa |
|---|---|
| ① | Os fins de linha. `is_finished()` compara o estado atual com este conjunto. |
| ② | O drone entra na blackboard **uma vez**. Todo estado o pega de lá. |
| ③ | Os parâmetros do ROS (que vêm do YAML) viram entradas da blackboard, **como `float`** — ver a regra 1 da seção 7. |
| ④ | Registrar um estado é dar-lhe um **nome**, e o nome é o que aparece nas transições. |
| ⑤ | `{outcome, próximo_estado}`. Sempre mapeie `"ERROR"`. |
| ⑥ | O estado por onde a missão começa. |

### 4.2 O nó ROS

Faz quatro coisas: declara os parâmetros com valores padrão (o launch
sobrescreve com o YAML), monta a FSM, cria o timer de 50 ms e publica a
trajetória para o RViz2. O `executeFSM()` do timer é onde a FSM avança:

```cpp
if (rclcpp::ok() && !fsm_->is_finished()) {
    fsm_->execute();
} else {
    RCLCPP_INFO(this->get_logger(), "FSM terminou com: %s", fsm_->get_fsm_outcome().c_str());
    rclcpp::shutdown();
}
```

E o `main` — com o detalhe que já custou tempo a mais de uma pessoa:

> O `Drone` **sobe o próprio executor e a própria thread de spin no
> construtor**. Adicioná-lo ao executor do `main` lança, em tempo de execução,
> `Node '/Drone' has already been added to an executor`. Só o nó da missão entra
> no executor.

---

## 5. Exercício: acrescente o estado HOVER

O objetivo: entre a decolagem e o pouso, pairar por um tempo configurável.
`ARMING → TAKEOFF → HOVER → LANDING → FINISHED`.

### 5.1 Escreva o estado

Crie `include/fase_treino/states/hover_state.hpp` — este arquivo compila como
está:

```cpp
#ifndef FASE_TREINO__STATES__HOVER_STATE_HPP_
#define FASE_TREINO__STATES__HOVER_STATE_HPP_

#include <memory>
#include <string>

#include <Eigen/Eigen>

#include "fsm/fsm.hpp"
#include "drone/Drone.hpp"
#include "stdstates/blackboard_params.hpp"

/**
 * @brief Paira na posição atual por `hover_time` segundos.
 *
 * Blackboard:
 *   entrada  "drone"       std::shared_ptr<Drone>
 *            "hover_time"  float, segundos
 *
 * Outcomes: ""            ainda pairando
 *           "HOVER DONE"  tempo cumprido
 *           "ERROR"       parâmetro ausente
 */
class HoverState : public fsm::State
{
public:
  HoverState()
  : fsm::State() {}

  void on_enter(fsm::Blackboard & blackboard) override
  {
    ok_ = false;                                   // ① nada de agir sem parâmetro

    auto * drone_ptr = blackboard.get<std::shared_ptr<Drone>>("drone");
    if (drone_ptr == nullptr) return;
    drone_ = *drone_ptr;

    drone_->log("");
    drone_->log("STATE: HOVER");                   // ② aparece no rosout e no rosbag

    if (!stdstates::require(blackboard, drone_, "hover_time", hover_time_)) return;   // ③

    pos_ = drone_->getLocalPosition();             // ④ o alvo é onde eu estou AGORA
    yaw_ = static_cast<float>(drone_->getOrientation()[2]);
    t0_ = drone_->getTime();
    ok_ = true;
  }

  std::string act(fsm::Blackboard & blackboard) override
  {
    (void)blackboard;
    if (!ok_) return "ERROR";

    if (drone_->getTime() - t0_ >= static_cast<double>(hover_time_)) {
      return "HOVER DONE";                         // ⑤ outcome: a FSM transita
    }

    drone_->setLocalPosition(                      // ⑥ reenviado a cada tick, de propósito
      static_cast<float>(pos_.x()),
      static_cast<float>(pos_.y()),
      static_cast<float>(pos_.z()),
      yaw_);

    return "";                                     // ⑦ continuo no estado
  }

  void on_exit(fsm::Blackboard & blackboard) override
  {
    (void)blackboard;
    if (drone_ != nullptr) {
      drone_->setLocalVelocity(0.0f, 0.0f, 0.0f, 0.0f);   // ⑧
    }
  }

private:
  std::shared_ptr<Drone> drone_{nullptr};
  Eigen::Vector3d pos_{0.0, 0.0, 0.0};
  float yaw_ = 0.0f;
  float hover_time_ = 0.0f;
  double t0_ = 0.0;
  bool ok_ = false;
};

#endif  // FASE_TREINO__STATES__HOVER_STATE_HPP_
```

O que cada marca ensina:

| | |
|---|---|
| ① ③ | `on_enter` **não pode devolver outcome**. O padrão da casa é uma flag `ok_`: o `require` falha, `ok_` fica `false`, e o `act` devolve `"ERROR"` no primeiro tick. É assim em todo o `stdstates`. |
| ② | Use `drone_->log()`, não `std::cout`: vai para o `/rosout`, e o `/rosout` está no rosbag de todo voo. |
| ④ | Leia a pose no `on_enter`, guarde, use no `act`. Reler a pose a cada tick e mandar o drone para "onde ele está" produz deriva. |
| ⑤ ⑦ | O contrato inteiro do `act`: `""` fica, string não vazia transita. |
| ⑥ | O PX4 **exige** setpoints contínuos no modo offboard — se pararem por ~0,5 s ele sai do offboard. Reenviar o mesmo alvo a cada tick é o correto. |
| ⑧ | Zere a velocidade ao sair. Um estado que sai deixando velocidade comandada empurra o drone durante o estado seguinte. |

> **Por que não `std::chrono` e `sleep`?** Porque `act` roda dentro do callback
> do timer: dormir ali congela o executor inteiro — telemetria e visão param
> junto. Tempo se mede comparando `drone_->getTime()` (ou
> `steady_clock::now()`) com o instante guardado no `on_enter`. Em 2025 um
> `on_exit` com `sleep_for(5s)` travou a missão exatamente assim; está
> documentado no [`return_home_state.hpp`](../src/stdstates/include/stdstates/return_home_state.hpp).

### 5.2 Ligue na FSM

Em `src/fase_treino.cpp`, três edições:

```cpp
// no topo, junto dos outros includes de estado
#include "fase_treino/states/hover_state.hpp"
```

```cpp
// no bloco ACRESCENTE dos estados
this->add_state("HOVER", std::make_unique<HoverState>());
```

```cpp
// a transição do TAKEOFF passa a apontar para HOVER, e HOVER para LANDING
this->add_transitions("TAKEOFF", {
    {"TAKEOFF COMPLETED", "HOVER"},
    {"ERROR", "ERROR"}
});

this->add_transitions("HOVER", {
    {"HOVER DONE", "LANDING"},
    {"ERROR", "ERROR"}
});
```

### 5.3 Declare o parâmetro nos três lugares

`hover_time` tem de existir em `default_params` (o padrão do código) **e** nos
dois YAML de `config/`. Esquecer o YAML não dá erro: o padrão do código
prevalece silenciosamente, e você passa vinte minutos se perguntando por que
mudar o YAML não mudou nada.

```cpp
// src/fase_treino.cpp, em default_params
{"hover_time", 3.0},        // segundos pairando
```

```yaml
# config/simulation.yaml E config/flight.yaml, sob ros__parameters
    hover_time: 3.0
```

### 5.4 Compile e rode

```bash
cd ~/evtol/dev
bash src/cbr2026/scripts/build.sh fase_treino
```

No log da missão você deve ver, em ordem:

```
STATE: TAKEOFF
Takeoff completed at altitude -2.50...
STATE: HOVER
STATE: LANDING
FSM terminou com: FINISHED
```

Se aparecer `STATE: HOVER` e nada mais por muito tempo, seu `act` nunca devolve
o outcome — comece pelo sinal do tempo. Se aparecer `ERRO: parametro ausente na
blackboard: 'hover_time'`, faltou a seção 5.3.

**Pronto: você construiu uma FSM.** Um estado próprio, um outcome, duas
transições e um parâmetro. Toda fase de competição é essa mesma estrutura com
mais nós no grafo — a [fase 1 da CBR 2026](../src/cbr2026/fase1/src/fase1.cpp)
tem oito estados e é lida do mesmo jeito.

---

## 6. Estados que você não precisa escrever

O [`stdstates`](../src/stdstates) traz onze estados que já voaram. **Antes de
escrever um estado, procure aqui.** Todos leem `"drone"` da blackboard, todos
devolvem `"ERROR"` se faltar parâmetro, e todos leem `float`.

| Estado | Outcomes (além de `""` e `"ERROR"`) | Chaves que exige |
|---|---|---|
| `ArmingState` | `ARMED` | — |
| `TakeoffState` | `TAKEOFF COMPLETED` | `takeoff_height`, `max_vertical_velocity`, `position_tolerance` |
| `LandingState` | `LANDED` | `landing_velocity_max/min`, `max_base_height`, `landing_timeout` |
| `PrecisionLandingState` | `LANDED` | `landing_velocity_max/min`, `max_base_height` |
| `LandAndDisarmState` | `DISARMED`, `TIMEOUT` | opcionais: `disarm_grace`, `disarm_timeout` |
| `GoToState` | `ARRIVED` | `target_x/y/z/yaw`, `position_tolerance` |
| `ReturnHomeState` | `AT HOME` | `home_position` (`Eigen::Vector3d`), `takeoff_height`, `max_horizontal_velocity`, `position_tolerance` |
| `WaypointListState` | `WAYPOINTS ENDED` | `waypoints` (`std::vector<ArenaPoint>`), `position_tolerance`, `max_horizontal_velocity` |
| `PrecisionAlignState` | `PRECISELY ALIGNED`, `LOST TARGET` | `align_target` (`Eigen::Vector3d`), `align_tolerance`, `align_descent_velocity`, `detection_timeout`, `pid_pos_kp/ki/kd`, `max_horizontal_velocity` |
| `YawSweepState` | *nenhum* — varre indefinidamente | `yaw_speed`, `search_yaw_range` |
| `AlignState` | `ALIGNED` | específico do alinhamento com mangueira da missão 2 (`hose_offset_y`, `hose_angle_error`, ganhos `align_*`) |

Dois padrões vale conhecer:

**Herde para especializar.** `YawSweepState` e `WaypointListState` nunca param
sozinhos, de propósito: eles fazem só o movimento. A missão que quer parar ao
encontrar algo **deriva** o estado, checa a sua condição primeiro e só então
chama a navegação da classe base. É o que faz o
[`SearchBaseState`](../src/cbr2026/fase1/include/fase1/states/search_base_state.hpp)
sobre o `WaypointListState`.

**`TakeoffState(false)` na redecolagem.** O construtor recebe `set_home`. Com
`true` (o padrão) ele **reancora o referencial do mundo** na posição atual — o
que é necessário na decolagem inicial e **destrutivo** em qualquer redecolagem:
tudo o que estava guardado em coordenadas passa a se referir a um referencial
que não existe mais. Foi o defeito que fez uma fase pousar na mesma base
indefinidamente, e o comentário de trinta linhas em
[`takeoff_state.hpp`](../src/stdstates/include/stdstates/takeoff_state.hpp)
conta a história com os números medidos em SITL.

---

## 7. As regras da casa

Nenhuma destas é preferência de estilo; cada uma é um bug que já aconteceu.

1. **`float`, nunca `double`, na blackboard.** O `get<T>` faz cast sem
   checagem. Gravar `double` e ler `float` compila, roda e devolve lixo. Os
   parâmetros do ROS chegam como `double` — converta na entrada, como o template
   faz.
2. **Use `stdstates::require` em vez de derreferenciar `get`.** Troca um
   segfault silencioso por `ERRO: parametro ausente na blackboard: 'x'`.
3. **Todo outcome precisa de transição.** Um outcome sem entrada no mapa lança
   `Outcome [X] doesn't belong to current state [Y]` **em tempo de execução** e
   mata a missão. Mapeie sempre `"ERROR"`.
4. **Nomes de estado e outcome são strings.** O compilador não confere nada:
   `"TAKEOF"` em `add_transitions` compila e só falha no voo. Copie e cole os
   nomes; não os digite duas vezes.
5. **Nada de bloquear no `act` (nem no `on_exit`).** Sem `sleep`, sem laço de
   espera, sem `*Sync` gratuito — o timer é o relógio da missão, e o callback é
   compartilhado com telemetria e visão.
6. **Parâmetro no YAML, nunca número no código.** Trocar simulação por voo real
   é trocar de arquivo. E variação de missão (busca em H em vez de linear) é
   parâmetro, não um pacote duplicado — `sae2026` tem `mission_1` e
   `mission_1_H`, que é exatamente o erro a não repetir.
7. **`on_exit` zera a velocidade.** Sempre.
8. **Se for usar PID, use `stdstates::kPidSampleTime` (0,04 s).** O padrão de
   0,05 s do `PidController` empata com o período do timer, e `compute()`
   devolve **0.0** — não o último valor — quando chamado antes do
   `sample_time`. O resultado é um drone "engasgando" que parece PID mal
   sintonizado.
9. **Visão escreve, estados leem.** A callback do detector escreve na
   blackboard; o estado só consulta. Nenhum estado assina tópico.
10. **Sobreponha `to_string()` se quiser ver o nome do estado no log.** O
    `RCLCPP_INFO` do template imprime `fsm_->get_current_state()`, que devolve o
    `to_string()` do estado — e a implementação padrão devolve **string
    vazia**. Nenhum estado do `stdstates` a sobrepõe hoje, então o campo sai
    vazio; é isso, não um bug do seu estado.

---

## 8. Checklist antes de voar

- [ ] `colcon build` limpo, sem warning novo
- [ ] Todo estado registrado com `add_state` **e** com transições ligadas
- [ ] `"ERROR"` mapeado em todos os estados
- [ ] Parâmetros novos nos **três** lugares (`default_params`, `simulation.yaml`, `flight.yaml`)
- [ ] Redecolagem usa `TakeoffState(false)`
- [ ] Nenhum `sleep` e nenhum número mágico no `.cpp`
- [ ] Rodou em SITL do começo ao fim, e o log terminou em `FINISHED`

---

## 9. Quando não funciona

| Sintoma | Causa quase certa |
|---|---|
| `Outcome [X] doesn't belong to current state [Y]` | outcome sem transição (regra 3) |
| `State does not exist` no start | nome errado em `add_transitions` ou `set_initial_state` |
| Segfault ao entrar num estado | derreferenciou `get` de chave ausente (regra 2) |
| `ERRO: parametro ausente na blackboard: 'x'` | parâmetro não declarado, ou nome diferente no YAML |
| Drone "engasga" com PID | `sample_time` igual ao período do timer (regra 8) |
| Redecola e revisita a mesma base | `set_home` verdadeiro na redecolagem (seção 6) |
| `Node '/Drone' has already been added to an executor` | o `Drone` foi para o executor do `main` |
| Sai do offboard sozinho | o estado parou de mandar setpoint em algum tick |
| O estado no log aparece vazio | `to_string()` não sobreposto (regra 10) |

Todo voo grava um rosbag em `~/evtol/mission_logs/` com `/rosout`,
`/drone_trajectory` e os tópicos do PX4. Depois de uma missão que deu errado, é
a única forma de saber o que o drone via:

```bash
ros2 bag play ~/evtol/mission_logs/<pasta>
ros2 topic echo /rosout
```

---

## 10. FSM ou BT?

Os dois motores existem no workspace e **executam os mesmos estados** — o
[`stdbt`](../src/stdbt) é um adaptador de sessenta linhas que expõe qualquer
`fsm::State` como ação de Behavior Tree. Escolher motor não é escolher
biblioteca de voo.

| Prefira **FSM** quando | Prefira **BT** quando |
|---|---|
| a missão é uma sequência com poucos desvios | há muita reação a condição que muda no meio da ação |
| o grafo é pequeno e cabe na cabeça | mudar a lógica sem recompilar tem valor (a árvore é um XML) |
| você quer o caminho mais batido — quase toda fase da equipe é FSM | você quer ver a lógica ao vivo no Groot2 |
| — | a mesma sub-lógica se repete em vários pontos (subtrees) |

O sintoma de que uma FSM está pedindo para virar BT: transições demais para o
mesmo lugar, estados que existem só para decidir, e a sensação de que o grafo
precisa de um diagrama para ser lido.

O caminho para o outro motor: [BT.md](BT.md).
