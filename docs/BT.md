# Como fazer uma Behavior Tree

**Para quem acabou de entrar na equipe.** Ao final deste documento você vai ter
uma missão em Behavior Tree que **arma, decola, vai até um ponto e pousa** —
primeiro editando só um arquivo XML, sem compilar nada, e depois com um nó
escrito por você.

Pré-requisitos: o workspace funcionando ([SETUP.md](SETUP.md),
[GUIA.md](GUIA.md)) e **[FSM.md](FSM.md) lido**. Não é formalidade: no nosso
workspace uma BT executa os mesmos estados que uma FSM, e metade do que você
precisa saber (blackboard, `on_enter`/`act`, tipos `float`, parâmetros em YAML)
está lá.

> Os links para `src/...` apontam para os repositórios que o `vcs import` traz —
> eles abrem no VS Code, não no GitHub deste repositório.

---

## Índice

1. [O modelo mental](#1-o-modelo-mental)
2. [A abordagem da equipe: uma BT não reimplementa nada](#2-a-abordagem-da-equipe-uma-bt-não-reimplementa-nada)
3. [Gere o pacote](#3-gere-o-pacote)
4. [Anatomia do que foi gerado](#4-anatomia-do-que-foi-gerado)
5. [Exercício A: uma missão inteira sem compilar](#5-exercício-a-uma-missão-inteira-sem-compilar)
6. [Exercício B: uma decisão na árvore](#6-exercício-b-uma-decisão-na-árvore)
7. [Exercício C: escreva um nó](#7-exercício-c-escreva-um-nó)
8. [Nós disponíveis](#8-nós-disponíveis)
9. [As regras da casa](#9-as-regras-da-casa)
10. [Checklist e diagnóstico](#10-checklist-e-diagnóstico)

---

## 1. O modelo mental

Numa FSM, o que liga uma coisa à outra são **transições nomeadas**: o estado
devolve `"ARMED"`, e um mapa diz para onde isso leva.

Numa Behavior Tree **não existem transições**. O que liga uma coisa à outra é a
**estrutura da árvore**. Cada nó, ao ser chamado (*ticked*), responde uma de
três coisas:

| Status | Significa |
|---|---|
| `SUCCESS` | terminei, deu certo |
| `FAILURE` | terminei, não deu |
| `RUNNING` | ainda estou nisso, me chame de novo no próximo tick |

E os nós **compostos** combinam essas respostas:

| Composto | Comportamento |
|---|---|
| `Sequence` | executa os filhos em ordem; **para no primeiro `FAILURE`**. É o "e depois". |
| `Fallback` | tenta os filhos em ordem; **para no primeiro `SUCCESS`**. É o "senão". |
| `Parallel` | roda os filhos ao mesmo tempo, com um critério de quantos precisam ter êxito |
| `RetryUntilSuccessful`, `Timeout`, `Inverter` | **decoradores**: modificam **um** filho |

A árvore inteira é chamada 20 vezes por segundo, do mesmo timer de 50 ms que
moveria uma FSM. Um tick desce a árvore a partir da raiz até encontrar o que
fazer agora.

```
Sequence                    ← tick entra aqui
├── Arming                  SUCCESS  (já armou nos ticks anteriores)
├── Takeoff                 SUCCESS
└── PrecisionLanding        RUNNING  ← é onde o tick está agora
```

E a estrutura substitui as transições assim:

```
FSM                                     BT
SEARCH BASE ──"BASE FOUND"────▶         <Fallback>
            ──"SEARCH ENDED"──▶           <BlackboardBool chave="terminou"/>
                                          <SeguirWaypoints/>
                                        </Fallback>
```

Duas consequências práticas, que são a razão de o motor existir aqui:

- **A árvore é um arquivo XML**, instalado em `share/<pacote>/trees/`. Mudar a
  lógica da missão é editar o XML e relançar — **sem recompilar**.
- **Dá para ver a árvore ao vivo.** Com o [Groot2](https://www.behaviortree.dev)
  conectado na porta do nó você vê qual nó está `RUNNING`, qual falhou e o valor
  de cada porta, enquanto o drone voa. É a maior vantagem sobre a FSM na hora de
  depurar.

---

## 2. A abordagem da equipe: uma BT não reimplementa nada

Esta é a parte que não está em nenhum tutorial de BT, e é a que importa aqui.

Os onze estados do [`stdstates`](../src/stdstates) já voaram: o perfil
exponencial de descida, o varrimento em guinada que não quebra em π, as guardas
contra parâmetro ausente. Reescrevê-los como nós de BT criaria duas cópias da
mesma lógica de voo, que divergiriam na primeira correção feita só de um lado —
é o problema do `PidController` em nove cópias que este workspace passou meses
eliminando.

Então o [`stdbt`](../src/stdbt) **não é uma reimplementação**. É um adaptador de
sessenta linhas
([`fsm_action_node.hpp`](../src/stdbt/include/stdbt/fsm_action_node.hpp)) que
expõe qualquer `fsm::State` como ação de BT:

| `fsm::State` | `FsmActionNode` |
|---|---|
| `on_enter` | `onStart()` → devolve `RUNNING` |
| `act` devolve `""` | `onRunning()` → `RUNNING` |
| `act` devolve outcome | `onRunning()` → `SUCCESS` (ou `FAILURE` se o outcome for `"ERROR"`) |
| `on_exit` | roda no fim **e também no `onHalted()`** |

**Para quais estados isso serve:** os de **resultado único** — armar, decolar,
pousar, voltar, desarmar. Um `ArmingState` que só pode terminar em `"ARMED"` é
exatamente uma ação que termina em `SUCCESS`.

**Para quais não serve:** os de **múltiplos outcomes**. Um estado que pode
terminar em `"BASE FOUND"` ou `"SEARCH ENDED"`, envolvido inteiro, daria um nó
que devolve `SUCCESS` nos dois casos — e a árvore perderia justamente a
informação que importa. Esses **não viram nó: viram estrutura**, com um
`Fallback` e uma condição.

> Se você precisou ler a porta `outcome` de um nó adaptado para decidir o que
> fazer em seguida, o que você queria era um `Fallback`.

### Como os parâmetros chegam aos nós

Os estados leem `fsm::Blackboard` — não a blackboard da BT. Em vez de traduzir
campo a campo, a missão põe um **ponteiro** para a blackboard da FSM dentro da
blackboard da BT, uma vez:

```cpp
auto bt_blackboard = BT::Blackboard::create();
bt_blackboard->set(stdbt::kFsmBlackboardKey, &blackboard_);   // &fsm::Blackboard
```

O efeito é bom: **uma missão em BT usa os mesmos YAML de parâmetros que uma
missão em FSM**, e os estados não sabem em qual motor estão rodando.

---

## 3. Gere o pacote

O mesmo gerador das missões em FSM, com uma bandeira:

```bash
cd ~/evtol/dev/src/cbr2026          # de dentro do repo da competição
~/evtol/dev/templates/new_mission.sh fase_bt --engine bt
```

O que sai (as três últimas linhas são o que a FSM não tem):

```
fase_bt/
├── package.xml  CMakeLists.txt
├── src/fase_bt.cpp                 carrega a árvore, registra os nós, tick de 20 Hz
├── config/{simulation,flight}.yaml
├── launch/{simulation,flight}.launch.py
├── trees/fase_bt.xml               ◀ A ÁRVORE: Arming → Takeoff → PrecisionLanding
├── include/fase_bt/nodes/
│   └── example_node.hpp            ◀ nó de exemplo, comentado, para copiar
└── test/test_tree.cpp              ◀ confere que todo nó do XML existe
```

```bash
cd ~/evtol/dev
bash src/cbr2026/scripts/build.sh fase_bt
```

E roda igual a qualquer missão — `ros2 launch fase_bt simulation.launch.py`, ou a
task **sim: iniciar com missão** do VS Code. O pacote gerado **já voa**: arma,
sobe, pousa.

---

## 4. Anatomia do que foi gerado

### 4.1 A árvore — `trees/fase_bt.xml`

```xml
<root BTCPP_format="4">
  <BehaviorTree ID="Principal">
    <Sequence>
      <Arming/>
      <Takeoff/>
      <PrecisionLanding/>
    </Sequence>
  </BehaviorTree>
</root>
```

É a missão inteira. `BTCPP_format="4"` é obrigatório (usamos a v4 do
BehaviorTree.CPP, a v3 tem API incompatível).

### 4.2 O nó ROS — `src/fase_bt.cpp`

Quatro passos, na ordem:

```cpp
// ① parâmetros do YAML → blackboard da FSM, como float
for (const auto &[key, value] : params) {
    if (std::holds_alternative<double>(value))
        blackboard_.set<float>(key, static_cast<float>(std::get<double>(value)));
    ...
}
blackboard_.set<std::shared_ptr<Drone>>("drone", drone_);

// ② fábrica: registra os nós do stdbt e os seus
BT::BehaviorTreeFactory factory;
stdbt::registerAll(factory);
// ACRESCENTE: factory.registerNodeType<MeuNo>("MeuNo");

// ③ a ponte entre as duas blackboards
auto bt_blackboard = BT::Blackboard::create();
bt_blackboard->set(stdbt::kFsmBlackboardKey, &blackboard_);

// ④ carrega o XML instalado (o nome do arquivo é parâmetro: tree_file)
tree_ = std::make_unique<BT::Tree>(factory.createTreeFromFile(caminho, bt_blackboard));
```

E o timer:

```cpp
const BT::NodeStatus status = tree_->tickOnce();     // NUNCA tickWhileRunning()
if (status != BT::NodeStatus::RUNNING) { /* terminou */ }
```

> **`tickWhileRunning()` é o exemplo da documentação oficial e está errado para
> nós.** Ele **bloqueia até a árvore terminar**; dentro do callback de um timer
> isso congela o executor — telemetria e visão param junto, com o drone no ar. O
> timer já dá o ritmo, do mesmo jeito que dá para a FSM.

### 4.3 O teste — `test/test_tree.cpp`

**Nome de nó errado no XML não é erro de compilação.** `<Takeof/>` em vez de
`<Takeoff/>` compila, instala, e só falha quando a missão tenta carregar a
árvore — no chão se você tiver sorte, no ar se não tiver.

O teste carrega o XML instalado com a mesma fábrica que a missão usa, e reprova
no CI se algum nó não existir. É o preço de a árvore ser um arquivo editável, e
vale a pena. Rode-o sempre depois de mexer no XML:

```bash
colcon test --packages-select fase_bt && colcon test-result --verbose
```

---

## 5. Exercício A: uma missão inteira sem compilar

Objetivo: `armar → decolar → ir até (2, 0, −2,5) → pousar com precisão → pousar e
desarmar`. Só editando arquivos de dados.

**Passo 1 — o alvo do `<GoTo/>`.** Esse nó lê `target_x/y/z/yaw` da blackboard, e
a blackboard vem do YAML. Acrescente em `config/simulation.yaml` **e** em
`config/flight.yaml`, dentro de `ros__parameters`, e também em `default_params`
no `.cpp` (a lista dos três lugares é a mesma regra da FSM):

```yaml
    target_x: 2.0
    target_y: 0.0
    target_z: -2.5      # FRD: negativo é para cima
    target_yaw: 0.0
```

> ⚠️ **`GoToState` lê esses quatro com `*blackboard.get<float>(...)` direto** —
> chave ausente é **segfault**, não mensagem de erro. Declare os quatro antes de
> usar `<GoTo/>`.

**Passo 2 — a árvore.** Edite `trees/fase_bt.xml`:

```xml
<root BTCPP_format="4">
  <BehaviorTree ID="Principal">
    <Sequence>
      <Arming/>
      <Takeoff/>
      <GoTo/>
      <PrecisionLanding/>
      <LandAndDisarm/>
    </Sequence>
  </BehaviorTree>
</root>
```

**Passo 3 — rode.** Recompile **uma vez**, porque o `default_params` está no
`.cpp`. O XML e os YAML são instalados como *symlink* para o `src/`, então a
partir daqui **editar a árvore ou os parâmetros não precisa de build** — só
relançar:

```bash
bash src/cbr2026/scripts/build.sh fase_bt
colcon test --packages-select fase_bt        # confere os nomes dos nós
ros2 launch fase_bt simulation.launch.py
```

Cinco nós, uma missão, nenhuma linha de C++. Esse é o ponto do motor.

---

## 6. Exercício B: uma decisão na árvore

Agora a parte que distingue BT de FSM: **decidir sem criar estado para isso.**
Queremos: *se a varredura já terminou, não vá a lugar nenhum; senão, vá até o
alvo.*

Numa FSM isso seria um estado que devolve dois outcomes. Aqui é um `Fallback`
com uma condição:

```xml
<root BTCPP_format="4">
  <BehaviorTree ID="Principal">
    <Sequence>
      <Arming/>
      <Takeoff/>

      <Fallback>
        <BlackboardBool chave="terminou_a_varredura"/>   <!-- pergunta -->
        <GoTo/>                                          <!-- ação -->
      </Fallback>

      <Timeout msec="20000">
        <PrecisionLanding/>
      </Timeout>
      <LandAndDisarm/>
    </Sequence>
  </BehaviorTree>
</root>
```

Leia em voz alta: *"ou a varredura terminou, ou então vá até o alvo"*. O
`Fallback` para no primeiro `SUCCESS`, então quando a condição é verdadeira o
`<GoTo/>` nunca é chamado.

As duas condições do `stdbt` cobrem quase tudo que as missões perguntam:

```xml
<BlackboardBool chave="terminou_a_varredura"/>              <!-- bool verdadeiro? -->
<BlackboardMenorQue chave="idade_da_deteccao" limite="5.0"/> <!-- float < limite? -->
```

Elas leem a **blackboard da FSM** — a mesma que a callback de visão da missão
escreve. Duas diferenças propositais entre as duas: chave ausente é **falso**
para `BlackboardBool` (a missão pode legitimamente não ter escrito ainda) e é
**`FAILURE`** para `BlackboardMenorQue` (não saber a idade de uma detecção não é
o mesmo que ela ser recente).

### `Sequence` ou `ReactiveSequence`?

| Composto | Ao reencontrar um filho já concluído |
|---|---|
| `Sequence` | **não** re-executa: retoma no filho que estava `RUNNING` |
| `ReactiveSequence` / `ReactiveFallback` | **re-tica desde o primeiro filho** a cada tick |

Os reativos são o motivo de existir uma BT: eles reavaliam a condição **enquanto
a ação roda**, e interrompem a ação (chamando `onHalted`) se a resposta mudar.

```xml
<!-- Persegue o alvo, e desiste no instante em que a detecção ficar velha -->
<ReactiveFallback>
  <Inverter>
    <BlackboardMenorQue chave="idade_da_deteccao" limite="5.0"/>
  </Inverter>
  <GoTo/>
</ReactiveFallback>
```

O preço: dentro de um reativo, **todo filho anterior roda de novo a cada tick**.
Um nó que escreve na blackboard ali é reexecutado 20 vezes por segundo — o que
pode ser exatamente o que você quer, ou um bug difícil.

---

## 7. Exercício C: escreva um nó

**Antes de escrever, pergunte se precisa.** Sete ações e duas condições já vêm
prontas (seção 8), e boa parte das decisões cabe nelas sem código nenhum.
Escreva um nó quando a missão tiver lógica própria: ver uma base, decidir se ela
é nova, contar quantas faltam.

Nosso caso: o `<GoTo/>` do exercício A tem o alvo fixo no YAML. Vamos escrever um
nó `SetTarget` que **escreve o alvo na blackboard**, para que a árvore possa
visitar vários pontos.

As três formas de nó, e quando usar cada uma:

| Classe base | Quando |
|---|---|
| `BT::SyncActionNode` | termina no mesmo tick: calcular, registrar, escrever na blackboard |
| `BT::StatefulActionNode` | ocupa vários ticks (`onStart`/`onRunning`/`onHalted`): **qualquer coisa que mova o drone** |
| `BT::ConditionNode` | só responde sim ou não, sem efeito colateral |

`SetTarget` só escreve — é síncrono. Crie
`include/fase_bt/nodes/set_target.hpp`:

```cpp
#ifndef FASE_BT__NODES__SET_TARGET_HPP_
#define FASE_BT__NODES__SET_TARGET_HPP_

#include <string>

#include <behaviortree_cpp/action_node.h>

#include "fsm/fsm.hpp"
#include "stdbt/fsm_action_node.hpp"   // kFsmBlackboardKey

/// Escreve target_x/y/z/yaw na blackboard da FSM, para o <GoTo/> ler.
class SetTarget : public BT::SyncActionNode
{
public:
  SetTarget(const std::string & nome, const BT::NodeConfig & config)
  : BT::SyncActionNode(nome, config) {}

  /// ① Portas são a interface do nó com o XML. Sem declarar, não dá para usar.
  static BT::PortsList providedPorts()
  {
    return {
      BT::InputPort<double>("x"),
      BT::InputPort<double>("y"),
      BT::InputPort<double>("z"),
      BT::InputPort<double>("yaw", 0.0, "rad")      // com valor padrão
    };
  }

  BT::NodeStatus tick() override
  {
    // ② A blackboard da FSM: a forma de DOIS argumentos devolve false quando a
    //    chave falta. A de um argumento LANÇA, no meio de um tick da árvore.
    fsm::Blackboard * bb = nullptr;
    auto bt_bb = config().blackboard;
    if (!bt_bb || !bt_bb->get<fsm::Blackboard *>(stdbt::kFsmBlackboardKey, bb) ||
      bb == nullptr)
    {
      return BT::NodeStatus::FAILURE;
    }

    double x = 0.0, y = 0.0, z = 0.0, yaw = 0.0;
    if (!getInput("x", x) || !getInput("y", y) || !getInput("z", z)) {
      return BT::NodeStatus::FAILURE;               // ③ porta faltando não é exceção
    }
    getInput("yaw", yaw);

    // ④ FLOAT, nunca double: o GoToState lê float, e o cast da blackboard da
    //    FSM não é checado — gravar double devolveria lixo.
    bb->set<float>("target_x", static_cast<float>(x));
    bb->set<float>("target_y", static_cast<float>(y));
    bb->set<float>("target_z", static_cast<float>(z));
    bb->set<float>("target_yaw", static_cast<float>(yaw));

    return BT::NodeStatus::SUCCESS;
  }
};

#endif  // FASE_BT__NODES__SET_TARGET_HPP_
```

**Registre em dois lugares** — e é fácil esquecer o segundo:

```cpp
// src/fase_bt.cpp, no bloco ACRESCENTE
#include "fase_bt/nodes/set_target.hpp"
...
factory.registerNodeType<SetTarget>("SetTarget");
```

```cpp
// test/test_tree.cpp, na fabricaDaMissao()  ← o teste tem a SUA PRÓPRIA fábrica
#include "fase_bt/nodes/set_target.hpp"
...
factory.registerNodeType<SetTarget>("SetTarget");
```

E use na árvore — agora com dois pontos, sem nada no YAML:

```xml
<root BTCPP_format="4">
  <BehaviorTree ID="Principal">
    <Sequence>
      <Arming/>
      <Takeoff/>

      <SetTarget x="2.0" y="0.0" z="-2.5"/>
      <GoTo/>

      <SetTarget x="2.0" y="2.0" z="-2.5"/>
      <GoTo/>

      <PrecisionLanding/>
      <LandAndDisarm/>
    </Sequence>
  </BehaviorTree>
</root>
```

```bash
bash src/cbr2026/scripts/build.sh fase_bt
colcon test --packages-select fase_bt        # o teste confere os dois SetTarget
ros2 launch fase_bt simulation.launch.py
```

> **Se o seu nó mover o drone**, ele é `StatefulActionNode` e **precisa** de
> `onHalted()` que zere a velocidade (`setLocalVelocity(0,0,0,0)`). A árvore pode
> interromper um nó a qualquer momento — um `Timeout`, um `ReactiveFallback` cuja
> condição mudou — e um nó interrompido no meio de um deslocamento deixaria o
> drone se movendo. O `include/fase_bt/nodes/example_node.hpp` gerado no seu
> pacote é justamente esse molde ([exemplo já no
> repositório](../src/cbr2026/fase4/include/fase4/nodes/example_node.hpp)).

---

## 8. Nós disponíveis

`stdbt::registerAll(factory)` — chamado pelo template — registra:

| Nó | O que faz | Chaves da blackboard |
|---|---|---|
| `<Arming/>` | arma | — |
| `<Takeoff/>` | decola **e reancora** o referencial do mundo | `takeoff_height`, `max_vertical_velocity`, `position_tolerance` |
| `<TakeoffAgain/>` | decola **sem** reancorar | idem |
| `<GoTo/>` | vai até `target_*` | `target_x/y/z/yaw`, `position_tolerance` |
| `<PrecisionLanding/>` | descida exponencial, tempo derivado | `landing_velocity_max/min`, `max_base_height` |
| `<ReturnHome/>` | volta em duas fases | `home_position`, `takeoff_height`, `max_horizontal_velocity`, `position_tolerance` |
| `<LandAndDisarm/>` | pousa e desarma sem bloquear | opcionais `disarm_grace`, `disarm_timeout` |
| `<BlackboardBool chave="k"/>` | condição: `bool` verdadeiro | a chave `k` |
| `<BlackboardMenorQue chave="k" limite="v"/>` | condição: `float` < limite | a chave `k` |

**As duas decolagens não são a mesma coisa.** `Takeoff` chama `setHomePosition`,
necessário depois de armar; `TakeoffAgain` não. Numa missão que pousa e redecola,
mover a origem do mundo invalida tudo o que já foi guardado em coordenadas — foi
o defeito que fez uma fase pousar na mesma base indefinidamente.

Os estados de **múltiplos outcomes** do `stdstates` (`WaypointListState`,
`PrecisionAlignState`, `YawSweepState`) **não** estão registrados, de propósito:
numa árvore eles se decompõem em ação + condição, e oferecê-los envolvidos
convidaria a escrever uma FSM em XML. Se precisar deles, adapte-os você —
`stdbt::FsmActionNode<MeuEstado>` é um template — e trate cada outcome como uma
ramificação da árvore, não como um valor a ler.

Além desses, todo o vocabulário do próprio BehaviorTree.CPP v4 está disponível —
os que a equipe usa, com os nomes **exatos** que o XML aceita:

| No XML | Porta | Observação |
|---|---|---|
| `<Sequence>` `<ReactiveSequence>` `<SequenceWithMemory>` | — | ver a distinção na seção 6 |
| `<Fallback>` `<ReactiveFallback>` | — | |
| `<Parallel>` | `success_count`, `failure_count` | |
| `<Inverter>` `<ForceSuccess>` `<ForceFailure>` | — | decoradores |
| `<RetryUntilSuccessful>` | `num_attempts` | **não existe `<Retry>`** |
| `<Repeat>` | `num_cycles` | |
| `<Timeout>` | `msec` | interrompe o filho (chama `onHalted`) |
| `<Delay>` | `delay_msec` | |
| `<SubTree ID="...">` | — | reaproveita uma `<BehaviorTree ID="...">` do mesmo arquivo |

> Dois nomes que enganam: o comentário do XML gerado e o README do `stdbt` falam
> em "Retry", mas o nó registrado é **`RetryUntilSuccessful`** — `<Retry/>` falha
> ao carregar com *Node not recognized*. E `<SetBlackboard>`, que existe no
> BehaviorTree.CPP, escreve na blackboard **da BT** — os estados do `stdstates`
> não leem de lá, e é por isso que o exercício C escreve um nó próprio.

Referência completa: **[behaviortree.dev](https://www.behaviortree.dev)**.

---

## 9. As regras da casa

1. **`tickOnce()`, nunca `tickWhileRunning()`.** O segundo bloqueia o executor.
2. **`onHalted()` desfaz o que o nó começou.** Sem ele, um nó interrompido
   durante um deslocamento deixa o drone se movendo.
3. **Nome errado no XML não é erro de compilação.** Rode `colcon test` depois de
   mexer na árvore; é para isso que o `test_tree.cpp` existe.
4. **Registre o nó nas duas fábricas** — a da missão e a do teste.
5. **`float` na blackboard da FSM, nunca `double`.** O cast não é checado.
6. **Não use a porta `outcome` para ramificar.** Se você chegou nisso, queria um
   `Fallback` com uma condição.
7. **Não escreva uma FSM em XML.** Uma árvore com um nó por "estado" e
   decoradores simulando transições tem as desvantagens dos dois motores. Se a
   missão é genuinamente sequencial e o grafo é pequeno, use FSM —
   [FSM.md](FSM.md).
8. **Parâmetro no YAML, valor no XML.** Números que a árvore usa como porta
   (`msec`, `x`, `limite`) podem ficar no XML; ganhos, tolerâncias e velocidades
   são parâmetros e vão para o YAML, nos três lugares.
9. **Portas declaradas em `providedPorts()`.** Um atributo no XML que não
   corresponde a uma porta declarada faz a árvore falhar ao carregar.
10. **A árvore de simulação e a de voo podem ser diferentes** — `tree_file` é
    parâmetro. Use isso em vez de comentar trechos do XML.

---

## 10. Checklist e diagnóstico

- [ ] `colcon build` limpo
- [ ] `colcon test --packages-select <fase>` passando (nomes de nó conferidos)
- [ ] Todo nó próprio registrado nas **duas** fábricas
- [ ] Todo `StatefulActionNode` com `onHalted()` que zera a velocidade
- [ ] `target_*` (ou o que os nós exigem) presente na blackboard antes do nó que lê
- [ ] Rodou em SITL do começo ao fim
- [ ] Groot2 aberto ao menos uma vez, para ver a árvore que você escreveu

| Sintoma | Causa quase certa |
|---|---|
| `não consegui carregar a árvore ...` no start | nome de nó ou de porta errado no XML (regra 3) |
| O teste passa, a missão não carrega | nó registrado só na fábrica do teste (regra 4) |
| Segfault ao entrar no `<GoTo/>` | `target_*` ausente na blackboard |
| Nó devolve `FAILURE` imediato, sem log | a blackboard da FSM não chegou: falta o `set(kFsmBlackboardKey, ...)` |
| Telemetria congela quando a árvore avança | `tickWhileRunning()` (regra 1) |
| Drone continua se movendo depois de um `Timeout` | falta `onHalted()` (regra 2) |
| Um nó reexecuta sem parar | está dentro de um `Reactive*` (seção 6) |
| Comparação de `float` sempre falha | gravado como `double` (regra 5) |
| Redecola e revisita o mesmo ponto | usou `<Takeoff/>` onde devia ser `<TakeoffAgain/>` |

**Groot2.** O parâmetro `groot2_port` (padrão `1667`, `0` desliga) publica a
árvore ao vivo. Abra o Groot2, conecte na porta e veja os nós piscando —
`RUNNING` em amarelo, `SUCCESS` em verde, `FAILURE` em vermelho — além do valor
de cada porta. Para uma missão que se comporta de forma inesperada, isso costuma
responder em trinta segundos o que o log responde em meia hora.

E todo voo grava rosbag em `~/evtol/mission_logs/`, com `/rosout` incluído.
