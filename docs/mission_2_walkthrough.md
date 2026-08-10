<!--
Este documento estava solto e NÃO VERSIONADO em `src/walkthrough.md` (maio/2026).
Foi trazido para cá na reorganização da raiz do workspace. É um registro
histórico da implementação da Missão 2 do SAE 2026 — útil como contexto, mas
não é a fonte da verdade sobre o código atual. Para o contrato vigente, veja
ARCHITECTURE.md.
-->

# Resumo da Implementação da Missão 2

A implementação da base estrutural da Missão 2 foi concluída com sucesso e compilada sem erros. Abaixo estão os detalhes do que foi feito:

## 1. Comunicação e Mensagens
- **`BallDetection.msg`**: Adicionamos essa nova mensagem no pacote `custom_msgs` contendo as informações `center_position`, `distance_estimate` e `is_detected`. O `CMakeLists.txt` e `package.xml` foram atualizados para incluir as dependências de `std_msgs` (para o `Header`).

## 2. Visão Computacional
- **Pacote `ball_detector`**: Foi criado um novo pacote Python no diretório `cv_nodes` contendo o nó base `ball_detector_node`. Ele assina o tópico de imagem da `horizontal_camera`, processa as informações (deixamos placeholders para o ajuste fino do OpenCV, usando *color mask*) e publica uma `BallDetection`.

## 3. Estados Padrão (`stdstates`)
Adicionamos dois novos estados genéricos:
- **`GoToState` (`goto_state.hpp`)**: Lê as coordenadas desejadas do *blackboard* e comanda o envio da posição para o drone.
- **`AlignState` (`align_state.hpp`)**: Estado genérico com dois PIDs. Através das *flags* do construtor, podemos habilitar ou desabilitar o controle de alinhamento em centro (Y) e yaw, tornando-o reaproveitável para diversas missões.

## 4. Estados Específicos da Missão 2
Todos foram criados no diretório `mission_2/states/`:
- **`SearchBallState`**: Roda o drone ao redor de seu próprio eixo (yaw) até detectar a bola.
- **`GoToBallState`**: Rastreia a bola via PID usando as coordenadas do centro vindas pelo tópico de visão, até que a distância cruze o limite (`trigger_distance`).
- **`RiseState`**: Altera a referência Z do drone em um delta de subida.
- **`DropTheHookState`**: Executa um *script* Python configurável para soltar o gancho através de chamada de sistema (`std::system`).

## 5. Máquina de Estados e Integração FSM
O `mission_2.cpp` foi reescrito:
- O nó principal `Mission2Node` agora declara **todos os parâmetros de ajuste**, incluindo PIDs, *yaw rate* e distâncias alvo, facilitando o ajuste via arquivo de configuração `.yaml` posteriormente.
- Foi implementado o *subscriber* `ball_detection` que, toda vez que uma mensagem é recebida, escreve no *blackboard* da FSM.
- A sequência lógica de decolagem, varredura, encontro, subida, alinhamento, soltura e retorno foi mapeada através das transições e estados de sucesso/falha.

> [!TIP]
> **Próximos Passos (Ajuste Fino):**
> 1. Ajustar as máscaras HSV do OpenCV em `ball_detector_node.py` com as cores reais da bola do cenário.
> 2. Criar ou validar os *launch files* YAML contendo os ganhos PID (`Kp, Ki, Kd`) ótimos para o seguimento e o alinhamento de forma simulada.
> 3. Escrever a lógica em `drop_hook.py` para atuar o servo do gancho.
