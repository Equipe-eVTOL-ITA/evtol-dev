<!--
    ARQUIVO GERADO. Nao edite a mao.

        python3 scripts/contratos.py

    O que esta aqui foi extraido do codigo. Para mudar uma linha deste
    documento, mude o codigo -- ou o bloco-ancora dentro dele -- e regenere.
    O CI reprova quando os dois discordam.
-->

# Contratos do workspace eVTOL

O que o sistema assume, tirado do proprio codigo.

**Este documento nao e a fonte da verdade: o codigo e.** Aqui e a vista dele,
reunida num lugar so para a hora em que se esta depurando um voo e nao da para
abrir sessenta arquivos. Se algo aqui parecer errado, o certo esta no arquivo
citado ao lado -- e entao este documento esta desatualizado, o que o
`--check` do CI existe para impedir.

Para acrescentar uma explicacao a este documento, escreva um bloco-ancora no
proprio codigo, onde ela pertence:

```cpp
// >>> CONTRATO frames.exemplo
// A explicacao, que continua morando junto do codigo que ela descreve.
// <<< CONTRATO
```


## Convencoes declaradas no codigo

### `frames.camera-optica`

Fonte: [src/vision_geometry/include/vision_geometry/ground_projector.hpp](src/vision_geometry/include/vision_geometry/ground_projector.hpp)

```
A camera na convencao do OpenCV: z para a FRENTE no eixo optico, x para a
DIREITA na imagem, y para BAIXO na imagem. O corpo em FRD.

Os extrinsecos sao a POSE DA CAMERA EXPRESSA NO CORPO. Em FRD, tz positivo
quer dizer camera ABAIXO do centro do drone.

Para a camera vertical, olhando para o chao, o mapeamento e:

    imagem +x        ->  corpo +Y (direita)
    imagem +y        ->  corpo -X (tras)
    eixo optico +Z   ->  corpo +Z (baixo)

Isso e roll=0, pitch=0, yaw=pi/2. O yaw NAO e pi/2 porque a camera esteja
fisicamente girada: e porque as convencoes de imagem e de corpo ja diferem
de 90 graus entre si.

CUIDADO. Extrinsecos NULOS tambem produzem uma camera "olhando para baixo" --
e com eles a direita da imagem vira a FRENTE do drone. Os dois olham para
baixo; um deles mede tudo 90 graus fora de lugar, sem erro nenhum. Os
configs de 2025 discordavam entre si sobre exatamente isto.

Erro de sinal aqui nao aparece como excecao: aparece como o drone pousando
no lugar errado.

INTRINSECOS: devem descrever a IMAGEM PUBLICADA pelo detector. Se o no de
camera recorta e redimensiona antes de publicar, calibre o fluxo publicado
ou use fromHorizontalFov(), que refaz a conta do recorte.
```

### `frames.fronteira-px4`

Fonte: [src/drone_lib/include/drone/Drone.hpp](src/drone_lib/include/drone/Drone.hpp)

```
O drone_lib e a UNICA camada que fala NED/FRD. Tudo acima dele -- stdstates,
as fases, as missoes -- trabalha no referencial da missao.

  NED / FRD   x para o NORTE, y para o LESTE, z para BAIXO (PX4)
              no corpo: x para a FRENTE, y para a DIREITA, z para BAIXO

O "FRD" devolvido por getLocalPosition() NAO e o corpo do drone: e um
referencial de MUNDO ancorado na decolagem -- origem na posicao em que
setHomePosition() foi chamada, eixo x no rumo daquele instante. Ele NAO gira
com o drone. Comandar y em setLocalPosition() e transladar para o lado
naquele referencial, e nao "ir para a direita do drone".

Os tres setpoints diferem no referencial, e essa e a armadilha:

  setLocalPosition(x,y,z,yaw)      mundo da decolagem; rotaciona so por initial_yaw_
  setLocalVelocity(vx,vy,vz,rate)  idem -- NAO e corpo. Para corpo, use o
                                   move_local_by_speed() do movement.hpp
  setMixedSetpoint(vx,vy,z,yaw)    XY em velocidade no CORPO de verdade
                                   (usa o yaw ATUAL), Z em posicao

z POSITIVO E PARA BAIXO. Uma velocidade z positiva DESCE.
```

### `movimento.politica`

Fonte: [src/drone_lib/include/drone/motion_policy.hpp](src/drone_lib/include/drone/motion_policy.hpp)

```
COMO o drone vai de um ponto a outro e uma chave de YAML, e nao codigo:

    motion_policy: holonomica   # padrao -- linha reta, inclusive de lado
    motion_policy: axial        # gira parado, so entao avanca; nunca de lado

Quem obedece: WaypointListState, GoToState e ReturnHomeState (stdstates), e
portanto toda missao que os usa. A fase4 ja voava axial por conta propria.

Quem NAO obedece, de proposito: PrecisionAlignState e o CentralizarNoComodo
da fase4. Sao correcoes de centimetros em malha fechada com a camera, e
girar antes de cada uma destruiria o alinhamento em vez de proteje-lo. Eles
perguntam permiteCorrecaoLateral() antes de comandar.

A lista completa de onde nasce um comando de movimento esta em
docs/CONTRATOS.md, secao "Onde se comanda movimento" -- gerada do codigo.
```

### `pouso.modos`

Fonte: [src/stdstates/include/stdstates/landing/registro.hpp](src/stdstates/include/stdstates/landing/registro.hpp)

```
A abordagem de pouso e uma chave de YAML, e nao codigo:

    landing_mode: exponencial   # padrao -- v(t) = v_max·e^(-t/tau)
    landing_mode: px4           # o modo LAND do firmware; TIRA de offboard
                                #   e DESARMA; ignora landing_velocity_*
    landing_mode: s_curve       # perfil em S, sem solavanco nas pontas

Parametros do exponencial e do s_curve: landing_velocity_max/min,
max_base_height, landing_timeout (folga, padrao 5 s).
Parametros do px4: disarm_grace (3 s), disarm_timeout (20 s).

max_base_height deveria ser NEGATIVO (FRD, para cima e negativo). Metade do
workspace escreve positivo; os dois sao aceitos, a magnitude e usada, e sai
um aviso no log da missao.

A altura de PARTIDA nunca e parametro: e medida ao entrar no estado.
```

### `px4.reancoragem-do-home`

Fonte: [src/stdstates/include/stdstates/takeoff_state.hpp](src/stdstates/include/stdstates/takeoff_state.hpp)

```
setHomePosition() REANCORA o referencial do mundo na posicao e no yaw atuais.
Use TakeoffState(true) SO na decolagem inicial da missao.

Numa redecolagem no meio da missao ela e destrutiva: a origem do mundo pula
para onde o drone estiver, e tudo o que estava guardado em coordenadas de
mundo -- bases ja visitadas, a grade de varredura, a posicao de casa --
passa a se referir a um referencial que nao existe mais.

Nao ha erro. O drone decola, olha para baixo, ve a base em que acabou de
pousar, nao a reconhece, e pousa nela de novo. E de novo.

Medido em SITL: o NED cru do PX4 ficou em (3.417, -0.159) o ciclo inteiro --
o drone nunca saiu do lugar -- enquanto o FRD visto pela missao saltava de
(-0.16, -3.03) para (0.00, 0.03) a cada redecolagem.
```

### `px4.sequencia-de-offboard`

Fonte: [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp)

```
A ordem para colocar o drone em offboard, e por que cada passo existe:

  1. waitForOdometry()   SEM ISSO, os setpoints do passo 2 dizem ao PX4
                         "segure em (0,0,0) NED" mesmo com o drone noutro
                         lugar -- current_pos_* ainda esta zerado.
  2. 20 setpoints a 10 Hz  O PX4 RECUSA entrar em offboard sem um fluxo de
                         setpoints ja chegando. Nao e opcional.
  3. VEHICLE_CMD_DO_SET_MODE param1=1 param2=6   (6 = OFFBOARD; 7 = POSCTL)
  4. armar
  5. setHomePosition()   DEPOIS de armar: antes, o EKF ainda nao convergiu
                         para o heading verdadeiro e initial_yaw_ fica em 0
                         enquanto o rumo real e outro.

E NAO HA WATCHDOG DE SETPOINT. O Drone so publica quando um estado chama
setLocal*(). Se o tick de 20 Hz da missao travar, o fluxo para e o PX4 sai
de offboard por falha de seguranca.
```

### `taxas.fsm-e-pid`

Fonte: [src/stdstates/include/stdstates/blackboard_params.hpp](src/stdstates/include/stdstates/blackboard_params.hpp)

```
A FSM roda a 20 Hz -- timer de 50 ms, em toda missao. E o relogio mestre do
sistema: os setpoints para o PX4 saem nessa taxa, porque o Drone so publica
quando um estado manda.

O sample_time dos PIDs e 0,04 s, e NAO 0,05. Nao e arredondamento: o
PidController::compute() devolve 0.0f -- e nao o ultimo valor -- quando
chamado antes de sample_time ter passado. Com os dois iguais, qualquer
jitter do escalonador produz zeros intermitentes na saida do controle, que
aparecem como um drone "engasgando" e se confundem com PID mal sintonizado.
0,04 s da 20% de folga.

Outras taxas do sistema: telemetria de posicao 20 Hz, status 2 Hz,
system_health 1 Hz, cameras 8-20 Hz conforme o no.
```

### `topicos.camera`

Fonte: [src/camera_publisher/camera_publisher/topicos.py](src/camera_publisher/camera_publisher/topicos.py)

```
O nome do topico de uma camera e:

    <papel>_camera/compressed        SEM /image/ NO MEIO
    <papel>_camera/raw

`papel` e a FUNCAO, nao o hardware: vertical, frontal, horizontal, gesto.
Trocar a camera nao pode trocar o topico.

POR QUE ISTO ESTA ESCRITO EM LETRA GRANDE

Ja houve tres formas em uso ao mesmo tempo -- /camera/image/compressed,
/vertical_camera/image/compressed, /vertical_camera/compressed -- e trocar de
camera trocava o topico enquanto o detector do outro lado seguia assinando o
antigo. Ele sobe, nao reclama, e nunca recebe quadro. A missao voa CEGA e o
log nao diz por que.

Isso ja aconteceu TRES VEZES neste workspace.

Antes de armar:  ros2 topic info -v <topico>
e desconfie de "Publisher count: 0".
```

## Onde se comanda movimento

Onde nasce um comando de movimento. **Esta e a tabela para consultar
quando a pergunta for "onde eu mexo para mudar como o drone anda".**

Os estados do `stdstates` passam pela `drone::MotionPolicy`, que se
escolhe com `motion_policy` no YAML da missao (`holonomica` ou `axial`).
As linhas abaixo que NAO citam `irPara` comandam o drone direto, e sao
as que uma mudanca de regra de movimento teria de tocar uma a uma.

| repositorio | arquivo:linha | funcao |
|---|---|---|
| cbr2026 | [src/cbr2026/fase1/include/fase1/states/search_base_state.hpp:85](src/cbr2026/fase1/include/fase1/states/search_base_state.hpp#L85) | act() -> setLocalVelocity |
| cbr2026 | [src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp:89](src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp#L89) | act() -> setMixedSetpoint |
| cbr2026 | [src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp:115](src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp#L115) | act() -> setMixedSetpoint |
| cbr2026 | [src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp:133](src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp#L133) | act() -> setMixedSetpoint |
| cbr2026 | [src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp:153](src/cbr2026/fase3/include/fase3/states/gesture_control_state.hpp#L153) | on_exit() -> setMixedSetpoint |
| cbr2026 | [src/cbr2026/fase3/include/fase3/states/search_hand_state.hpp:54](src/cbr2026/fase3/include/fase3/states/search_hand_state.hpp#L54) | act() -> setLocalVelocity |
| cbr2026 | [src/cbr2026/fase4/include/fase4/nodes/contexto.hpp:269](src/cbr2026/fase4/include/fase4/nodes/contexto.hpp#L269) | atualizarVies() -> setLocalPosition |
| cbr2026 | [src/cbr2026/fase4/include/fase4/nodes/contexto.hpp:278](src/cbr2026/fase4/include/fase4/nodes/contexto.hpp#L278) | atualizarVies() -> setLocalPosition |
| cbr2026 | [src/cbr2026/fase4/include/fase4/nodes/contexto.hpp:295](src/cbr2026/fase4/include/fase4/nodes/contexto.hpp#L295) | parar() -> setLocalPosition |
| cbr2026 | [src/cbr2026/fase4/include/fase4/nodes/example_node.hpp:91](src/cbr2026/fase4/include/fase4/nodes/example_node.hpp#L91) | onHalted() -> setLocalVelocity |
| cbr2026 | [src/cbr2026/fase4/include/fase4/nodes/navegacao.hpp:127](src/cbr2026/fase4/include/fase4/nodes/navegacao.hpp#L127) | onRunning() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/motion_policy.cpp:20](src/drone_lib/src/motion_policy.cpp#L20) | MotionPolicy::irPara() -> irPara |
| drone_lib | [src/drone_lib/src/motion_policy.cpp:34](src/drone_lib/src/motion_policy.cpp#L34) | MotionPolicy::irPara() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/motion_policy.cpp:47](src/drone_lib/src/motion_policy.cpp#L47) | MotionPolicy::parar() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/movement.cpp:17](src/drone_lib/src/movement.cpp#L17) | move_local_by_speed() -> setLocalVelocity |
| drone_lib | [src/drone_lib/src/movement.cpp:23](src/drone_lib/src/movement.cpp#L23) | move_local_by_speed() -> setLocalVelocity |
| drone_lib | [src/drone_lib/src/movement.cpp:31](src/drone_lib/src/movement.cpp#L31) | move_local_by_vel_as_position() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/movement.cpp:50](src/drone_lib/src/movement.cpp#L50) | move_local_by_vel_as_position() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/movement.cpp:65](src/drone_lib/src/movement.cpp#L65) | move_local_by_vel_as_position() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/movement.cpp:85](src/drone_lib/src/movement.cpp#L85) | move_local_by_vel_as_position() -> setLocalPosition |
| drone_lib | [src/drone_lib/src/movement.cpp:109](src/drone_lib/src/movement.cpp#L109) | move_local_by_vel_as_position() -> setLocalPosition |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp:91](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp#L91) | act() -> move_local_constant_step |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp:92](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp#L92) | act() -> setLocalVelocity |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp:104](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/advance_state.hpp#L104) | act() -> setLocalVelocity |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp:98](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp#L98) | act() -> setLocalVelocity |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp:114](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp#L114) | act() -> setLocalVelocity |
| ensaio_em_voo | [src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp:122](src/ensaio_em_voo/teste_yaw/include/teste_yaw/states/rotate_state.hpp#L122) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp:87](src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp#L87) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp:96](src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp#L96) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp:113](src/sae2026/mission_1/include/mission_1/states/descend_for_shape_state.hpp#L113) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/go_to_aruco_state.hpp:86](src/sae2026/mission_1/include/mission_1/states/go_to_aruco_state.hpp#L86) | act() -> move_local_by_speed |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/go_to_aruco_state.hpp:112](src/sae2026/mission_1/include/mission_1/states/go_to_aruco_state.hpp#L112) | act() -> move_local_by_speed |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/go_to_base_state.hpp:61](src/sae2026/mission_1/include/mission_1/states/go_to_base_state.hpp#L61) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/go_to_base_state.hpp:92](src/sae2026/mission_1/include/mission_1/states/go_to_base_state.hpp#L92) | act() -> move_local_by_speed |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp:62](src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp#L62) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp:79](src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp#L79) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp:80](src/sae2026/mission_1/include/mission_1/states/initial_aruco_search_state.hpp#L80) | act() -> move_local_by_vel_as_position |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/search_aruco_state.hpp:128](src/sae2026/mission_1/include/mission_1/states/search_aruco_state.hpp#L128) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/search_aruco_state.hpp:166](src/sae2026/mission_1/include/mission_1/states/search_aruco_state.hpp#L166) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/search_base_state.hpp:122](src/sae2026/mission_1/include/mission_1/states/search_base_state.hpp#L122) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1/include/mission_1/states/search_base_state.hpp:147](src/sae2026/mission_1/include/mission_1/states/search_base_state.hpp#L147) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/descend_for_shape_state.hpp:97](src/sae2026/mission_1_H/include/mission_1/states/descend_for_shape_state.hpp#L97) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/go_to_aruco_state.hpp:86](src/sae2026/mission_1_H/include/mission_1/states/go_to_aruco_state.hpp#L86) | act() -> move_local_by_speed |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/go_to_aruco_state.hpp:112](src/sae2026/mission_1_H/include/mission_1/states/go_to_aruco_state.hpp#L112) | act() -> move_local_by_speed |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/go_to_base_state.hpp:82](src/sae2026/mission_1_H/include/mission_1/states/go_to_base_state.hpp#L82) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/go_to_base_state.hpp:106](src/sae2026/mission_1_H/include/mission_1/states/go_to_base_state.hpp#L106) | act() -> setMixedSetpoint |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/h_search_base_state.hpp:131](src/sae2026/mission_1_H/include/mission_1/states/h_search_base_state.hpp#L131) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/initial_aruco_search_state.hpp:63](src/sae2026/mission_1_H/include/mission_1/states/initial_aruco_search_state.hpp#L63) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/initial_aruco_search_state.hpp:81](src/sae2026/mission_1_H/include/mission_1/states/initial_aruco_search_state.hpp#L81) | act() -> move_local_by_vel_as_position |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/search_aruco_state.hpp:128](src/sae2026/mission_1_H/include/mission_1/states/search_aruco_state.hpp#L128) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/search_aruco_state.hpp:166](src/sae2026/mission_1_H/include/mission_1/states/search_aruco_state.hpp#L166) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/search_base_state.hpp:122](src/sae2026/mission_1_H/include/mission_1/states/search_base_state.hpp#L122) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_1_H/include/mission_1/states/search_base_state.hpp:147](src/sae2026/mission_1_H/include/mission_1/states/search_base_state.hpp#L147) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/approach_hose_state.hpp:67](src/sae2026/mission_2/include/mission_2/states/approach_hose_state.hpp#L67) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/approach_hose_state.hpp:79](src/sae2026/mission_2/include/mission_2/states/approach_hose_state.hpp#L79) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp:67](src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp#L67) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp:91](src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp#L91) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp:118](src/sae2026/mission_2/include/mission_2/states/goto_ball_state.hpp#L118) | move_local_constant_step() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/lookat_ball_state.hpp:74](src/sae2026/mission_2/include/mission_2/states/lookat_ball_state.hpp#L74) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/lookat_ball_state.hpp:122](src/sae2026/mission_2/include/mission_2/states/lookat_ball_state.hpp#L122) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp:135](src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp#L135) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp:183](src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp#L183) | act() -> setMixedSetpoint |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp:209](src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp#L209) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp:237](src/sae2026/mission_2/include/mission_2/states/mangueira_align_state.hpp#L237) | act() -> setMixedSetpoint |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/rise_state.hpp:107](src/sae2026/mission_2/include/mission_2/states/rise_state.hpp#L107) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/rise_state.hpp:128](src/sae2026/mission_2/include/mission_2/states/rise_state.hpp#L128) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp:110](src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp#L110) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp:128](src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp#L128) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp:163](src/sae2026/mission_2/include/mission_2/states/search_ball_state.hpp#L163) | act() -> move_local_constant_step |
| sae2026 | [src/sae2026/mission_3/include/mission_3/align_state.hpp:89](src/sae2026/mission_3/include/mission_3/align_state.hpp#L89) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/align_state.hpp:120](src/sae2026/mission_3/include/mission_3/align_state.hpp#L120) | act() -> setMixedSetpoint |
| sae2026 | [src/sae2026/mission_3/include/mission_3/approach_state.hpp:74](src/sae2026/mission_3/include/mission_3/approach_state.hpp#L74) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/approach_state.hpp:79](src/sae2026/mission_3/include/mission_3/approach_state.hpp#L79) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/approach_state.hpp:88](src/sae2026/mission_3/include/mission_3/approach_state.hpp#L88) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/goto_state.hpp:85](src/sae2026/mission_3/include/mission_3/goto_state.hpp#L85) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/photo_state.hpp:35](src/sae2026/mission_3/include/mission_3/photo_state.hpp#L35) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/search_state.hpp:78](src/sae2026/mission_3/include/mission_3/search_state.hpp#L78) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/search_state.hpp:101](src/sae2026/mission_3/include/mission_3/search_state.hpp#L101) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_3/include/mission_3/termination_state.hpp:66](src/sae2026/mission_3/include/mission_3/termination_state.hpp#L66) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_teste/include/mission_teste/align_state.hpp:104](src/sae2026/mission_teste/include/mission_teste/align_state.hpp#L104) | act() -> setLocalPosition |
| sae2026 | [src/sae2026/mission_teste/include/mission_teste/align_state.hpp:126](src/sae2026/mission_teste/include/mission_teste/align_state.hpp#L126) | act() -> setMixedSetpoint |
| sae2026 | [src/sae2026/mission_teste/include/mission_teste/go_to_test.hpp:70](src/sae2026/mission_teste/include/mission_teste/go_to_test.hpp#L70) | act() -> setLocalPosition |
| stdstates | [src/stdstates/include/stdstates/align_state.hpp:66](src/stdstates/include/stdstates/align_state.hpp#L66) | act() -> setLocalPosition |
| stdstates | [src/stdstates/include/stdstates/align_state.hpp:92](src/stdstates/include/stdstates/align_state.hpp#L92) | act() -> move_local_constant_step |
| stdstates | [src/stdstates/include/stdstates/goto_state.hpp:54](src/stdstates/include/stdstates/goto_state.hpp#L54) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/goto_state.hpp:59](src/stdstates/include/stdstates/goto_state.hpp#L59) | act() -> irPara |
| stdstates | [src/stdstates/include/stdstates/land_and_disarm_state.hpp:66](src/stdstates/include/stdstates/land_and_disarm_state.hpp#L66) | on_enter() -> land |
| stdstates | [src/stdstates/include/stdstates/land_and_disarm_state.hpp:100](src/stdstates/include/stdstates/land_and_disarm_state.hpp#L100) | act() -> disarm |
| stdstates | [src/stdstates/include/stdstates/landing/estrategia.hpp:41](src/stdstates/include/stdstates/landing/estrategia.hpp#L41) | encerrar() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/landing/exponencial.hpp:84](src/stdstates/include/stdstates/landing/exponencial.hpp#L84) | passo() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/landing/exponencial.hpp:93](src/stdstates/include/stdstates/landing/exponencial.hpp#L93) | passo() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/landing/px4_land.hpp:43](src/stdstates/include/stdstates/landing/px4_land.hpp#L43) | preparar() -> land |
| stdstates | [src/stdstates/include/stdstates/landing/px4_land.hpp:67](src/stdstates/include/stdstates/landing/px4_land.hpp#L67) | passo() -> disarm |
| stdstates | [src/stdstates/include/stdstates/landing/s_curve.hpp:76](src/stdstates/include/stdstates/landing/s_curve.hpp#L76) | passo() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/landing/s_curve.hpp:90](src/stdstates/include/stdstates/landing/s_curve.hpp#L90) | passo() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/next_waypoints.hpp:102](src/stdstates/include/stdstates/next_waypoints.hpp#L102) | navigate() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/next_waypoints.hpp:115](src/stdstates/include/stdstates/next_waypoints.hpp#L115) | navigate() -> irPara |
| stdstates | [src/stdstates/include/stdstates/precision_align_state.hpp:103](src/stdstates/include/stdstates/precision_align_state.hpp#L103) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/precision_align_state.hpp:120](src/stdstates/include/stdstates/precision_align_state.hpp#L120) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/precision_align_state.hpp:139](src/stdstates/include/stdstates/precision_align_state.hpp#L139) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/precision_align_state.hpp:164](src/stdstates/include/stdstates/precision_align_state.hpp#L164) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/return_home_state.hpp:120](src/stdstates/include/stdstates/return_home_state.hpp#L120) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/return_home_state.hpp:140](src/stdstates/include/stdstates/return_home_state.hpp#L140) | act() -> irPara |
| stdstates | [src/stdstates/include/stdstates/return_home_state.hpp:147](src/stdstates/include/stdstates/return_home_state.hpp#L147) | act() -> setLocalVelocity |
| stdstates | [src/stdstates/include/stdstates/return_home_state.hpp:151](src/stdstates/include/stdstates/return_home_state.hpp#L151) | act() -> irPara |
| stdstates | [src/stdstates/include/stdstates/takeoff_state.hpp:139](src/stdstates/include/stdstates/takeoff_state.hpp#L139) | act() -> move_local_constant_step |
| stdstates | [src/stdstates/include/stdstates/yaw_sweep_state.hpp:106](src/stdstates/include/stdstates/yaw_sweep_state.hpp#L106) | sweep() -> setLocalVelocity |

Total: **107** pontos.

## Topicos

### cbr2026

publica: `/drone_trajectory`, `/telemetry/bases`

assina: `/scan`

### cv_nodes

publica: `/annotated_image/compressed`, `/base_detector/debug/bbox/compressed`, `/base_detector/debug/mask/compressed`, `/gesture_detector/debug/compressed`, `/gesture_detector/gestures`, `/gesture_detector/hand_location`, `/mangueira/angle`, `/mangueira/detections`, `/mangueira/position`, `/mangueira_detector/image/compressed`, `/mangueira_detector/mask/compressed`, `/manometer_error`, `/manometro_debug/compressed`, `/measured_pressure`, `/position_manometer`, `/qr_code_string`, `/vertical_classification`, `/window_detector/annotated`, `/window_detector/mask`, `ball_detection`, `ball_detection_image/compressed`, `ball_detector/mask/compressed`, `bouncing_detection`, `bouncing_detection_image/compressed`, `centroid`, `threshold`, `window_found`

assina: `/pressure_analysis`

### drone_lib

publica: `/telemetry/drone_status`, `/telemetry/logs`, `/telemetry/position`, `/telemetry/system_health`

### ensaio_em_voo

publica: `/drone_trajectory`

### ozzy_bridge

publica: `/ozzy/cmd_vel`

assina: `/ozzy/armed`, `/ozzy/diagnostics`, `/ozzy/mode`, `/ozzy/pose`, `/ozzy/statustext`

### sae2026

publica: `/discovered_bases`, `/drone_trajectory`, `/mission_1/base_markers`, `/mission_1_H/base_markers`, `/pressure_analysis`

assina: `/bouncing_detection`, `/mangueira/angle`, `/mangueira/position`, `/manometer_error`, `/measured_pressure`, `ball_detection`, `bouncing_detection`

### sim2d

publica: `/fmu/in/trajectory_setpoint`, `/fmu/in/vehicle_command`, `/fmu/out/timesync_status`, `/fmu/out/vehicle_odometry`, `/fmu/out/vehicle_status`

assina: `/fmu/in/trajectory_setpoint`, `/fmu/in/vehicle_command`, `/fmu/out/vehicle_odometry`

### telemetry_handler

publica: `/base_markers`, `/drone/path`, `/drone/pose`, `/drone/twist`

## Frequencias

| arquivo | periodo | taxa |
|---|---|---|
| [src/camera_publisher/camera_publisher/imx_219.py](src/camera_publisher/camera_publisher/imx_219.py) | 0.1 s | 10 Hz |
| [src/camera_publisher/camera_publisher/raspicam_publisher.py](src/camera_publisher/camera_publisher/raspicam_publisher.py) | 0.1 s | 10 Hz |
| [src/cbr2026/fase1/src/fase1.cpp](src/cbr2026/fase1/src/fase1.cpp) | 50 milliseconds | 20 Hz |
| [src/cbr2026/fase3/src/fase3.cpp](src/cbr2026/fase3/src/fase3.cpp) | 50 milliseconds | 20 Hz |
| [src/cbr2026/fase4/src/fase4.cpp](src/cbr2026/fase4/src/fase4.cpp) | 50 milliseconds | 20 Hz |
| [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) | 50 milliseconds | 20 Hz |
| [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) | 500 milliseconds | 2 Hz |
| [src/drone_lib/src/system_health.cpp](src/drone_lib/src/system_health.cpp) | 1 seconds | 1 Hz |
| [src/ensaio_em_voo/teste_grid_quadrado/src/teste_grid_quadrado.cpp](src/ensaio_em_voo/teste_grid_quadrado/src/teste_grid_quadrado.cpp) | 50 milliseconds | 20 Hz |
| [src/ensaio_em_voo/teste_yaw/src/teste_yaw.cpp](src/ensaio_em_voo/teste_yaw/src/teste_yaw.cpp) | 50 milliseconds | 20 Hz |
| [src/ozzy_bridge/ozzy_bridge/link_monitor.py](src/ozzy_bridge/ozzy_bridge/link_monitor.py) | 1 s | 1 Hz |
| [src/ozzy_bridge/ozzy_bridge/teleop.py](src/ozzy_bridge/ozzy_bridge/teleop.py) | 1 s | 1 Hz |
| [src/sae2026/mission_1/src/mission_1.cpp](src/sae2026/mission_1/src/mission_1.cpp) | 50 milliseconds | 20 Hz |
| [src/sae2026/mission_1_H/src/mission_1_H.cpp](src/sae2026/mission_1_H/src/mission_1_H.cpp) | 50 milliseconds | 20 Hz |
| [src/sae2026/mission_2/src/mission_2.cpp](src/sae2026/mission_2/src/mission_2.cpp) | 50 milliseconds | 20 Hz |
| [src/sae2026/mission_2/src/mission_2.cpp](src/sae2026/mission_2/src/mission_2.cpp) | 500 milliseconds | 2 Hz |
| [src/sae2026/mission_3/src/mission_3.cpp](src/sae2026/mission_3/src/mission_3.cpp) | 50 milliseconds | 20 Hz |
| [src/sae2026/mission_teste/src/mission_teste.cpp](src/sae2026/mission_teste/src/mission_teste.cpp) | 50 milliseconds | 20 Hz |
| [src/sim2d/sim2d/missao_reta.py](src/sim2d/sim2d/missao_reta.py) | 0.05 s | 20 Hz |
| [src/sim2d/sim2d/no.py](src/sim2d/sim2d/no.py) | 0.05 s | 20 Hz |
| [src/sim2d/sim2d/no.py](src/sim2d/sim2d/no.py) | 0.1 s | 10 Hz |
| [src/sim2d/sim2d/no.py](src/sim2d/sim2d/no.py) | 0.2 s | 5 Hz |
| [src/telemetry_handler/telemetry_handler/telemetry_handler.py](src/telemetry_handler/telemetry_handler/telemetry_handler.py) | 5 s | 0.2 Hz |

## Comandos do PX4 em uso

| comando | onde |
|---|---|
| `VEHICLE_CMD_COMPONENT_ARM_DISARM` | [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) |
| `VEHICLE_CMD_DO_CHANGE_SPEED` | [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) |
| `VEHICLE_CMD_DO_SET_MODE` | [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) |
| `VEHICLE_CMD_NAV_LAND` | [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) |
| `VEHICLE_CMD_NAV_TAKEOFF` | [src/drone_lib/src/Drone.cpp](src/drone_lib/src/Drone.cpp) |

## Parametros: simulacao x voo

So o que **difere** entre `simulation.yaml` e `flight.yaml`. E esse
diff que interessa antes de voar: o que e igual nos dois ja foi
exercitado na simulacao.

### fase1

| parametro | simulacao | voo |
|---|---|---|
| `base_detector.blue_lower` | [100, 80, 50] | [95, 60, 40] |
| `base_detector.blue_upper` | [130, 255, 255] | [135, 255, 255] |
| `base_detector.debug_jpeg_quality` | 60 | 50 |
| `base_detector.debug_mask` | True | False |
| `base_detector.debug_publish_rate` | 5.0 | 2.0 |
| `base_detector.processing_frequency` | 15.0 | 8.0 |
| `base_detector.yellow_lower` | [10, 100, 100] | [8, 80, 80] |
| `base_detector.yellow_upper` | [40, 255, 255] | [45, 255, 255] |
| `fase1_node.align_descent_velocity` | 0.15 | 0.1 |
| `fase1_node.align_tolerance` | 0.1 | 0.15 |
| `fase1_node.detection_timeout` | 5.0 | 8.0 |
| `fase1_node.grid_step_x` | -1.5 | -1.2 |
| `fase1_node.grid_y_length` | -5.5 | -5.1 |
| `fase1_node.landing_mode` | exponencial | px4 |
| `fase1_node.landing_velocity_max` | 0.5 | 0.35 |
| `fase1_node.landing_velocity_min` | 0.2 | 0.15 |
| `fase1_node.max_horizontal_velocity` | 1.0 | 0.7 |
| `fase1_node.max_vertical_velocity` | 1.2 | 0.8 |
| `fase1_node.motion_policy` | holonomica | axial |
| `fase1_node.pid_pos_kd` | 0.05 | 0.08 |
| `fase1_node.pid_pos_kp` | 1.0 | 0.7 |
| `fase1_node.position_tolerance` | 0.15 | 0.25 |
| `fase1_node.target_association_radius` | 1.0 | 1.2 |
| `fase1_vision.camera_height` | 800 | 480 |
| `fase1_vision.camera_width` | 800 | 640 |
| `fase1_vision.pnp_max_plane_deviation` | 1.5 | 1.8 |
| `fase1_vision.published_size` | 800 | 480 |
| `webcam_publisher.camera_name` | — | vertical |
| `webcam_publisher.frame_height` | — | 480 |
| `webcam_publisher.frame_width` | — | 640 |
| `webcam_publisher.jpeg_quality` | — | 70 |
| `webcam_publisher.publish_rate` | — | 10.0 |

### fase3

| parametro | simulacao | voo |
|---|---|---|
| `fase3_node.climb_pid_kd` | 0.09 | 0.12 |
| `fase3_node.climb_pid_kp` | 0.9 | 0.6 |
| `fase3_node.control_speed` | 0.4 | 0.25 |
| `fase3_node.detection_timeout` | 3.0 | 5.0 |
| `fase3_node.landing_velocity_max` | 0.5 | 0.35 |
| `fase3_node.landing_velocity_min` | 0.2 | 0.15 |
| `fase3_node.max_horizontal_velocity` | 1.0 | 0.6 |
| `fase3_node.max_vertical_velocity` | 1.0 | 0.7 |
| `fase3_node.position_tolerance` | 0.15 | 0.25 |
| `fase3_node.yaw_pid_kd` | 0.06 | 0.08 |
| `fase3_node.yaw_pid_kp` | 0.6 | 0.4 |
| `fase3_node.yaw_speed` | 0.35 | 0.25 |
| `gesture_detector.debug_jpeg_quality` | 70 | 50 |
| `gesture_detector.debug_max_width` | 480 | 320 |
| `gesture_detector.debug_publish_rate` | 5.0 | 2.0 |
| `gesture_detector.gesture_debounce` | 5 | 4 |
| `gesture_detector.image_topic` | /frontal_camera/compressed | /gesto_camera/compressed |
| `gesture_detector.processing_frequency` | 15.0 | 8.0 |
| `roi_stream.camera_name` | — | gesto |
| `roi_stream.input_topic` | — | /oak/left/image_rect |
| `roi_stream.jpeg_quality` | — | 50 |
| `roi_stream.output_height` | — | 0 |
| `roi_stream.output_width` | — | 0 |
| `roi_stream.publish_rate` | — | 8.0 |
| `roi_stream.roi_height` | — | 400 |
| `roi_stream.roi_width` | — | 400 |
| `roi_stream.roi_x` | — | -1 |
| `roi_stream.roi_y` | — | -1 |
| `webcam_publisher.camera_name` | frontal | — |
| `webcam_publisher.frame_height` | 480 | — |
| `webcam_publisher.frame_width` | 640 | — |
| `webcam_publisher.horizontal_flip` | True | — |
| `webcam_publisher.jpeg_quality` | 70 | — |
| `webcam_publisher.publish_rate` | 15.0 | — |
| `webcam_publisher.use_compressed` | True | — |
| `webcam_publisher.vertical_flip` | False | — |
| `webcam_publisher.video_source` | /dev/video0 | — |

### fase4

| parametro | simulacao | voo |
|---|---|---|
| `fase4_node.ciclos_estaveis` | 5.0 | 10.0 |
| `fase4_node.landing_velocity_max` | 0.5 | 0.35 |
| `fase4_node.landing_velocity_min` | 0.15 | 0.12 |
| `fase4_node.lidar_offset_frente` | 0.0 | 0.053 |
| `fase4_node.max_horizontal_velocity` | 1.5 | 0.4 |
| `fase4_node.max_vertical_velocity` | 1.2 | 0.7 |
| `fase4_node.position_tolerance` | 0.15 | 0.25 |
| `fase4_node.scan_parede_min` | 0.2 | 0.25 |
| `fase4_node.scan_salto_max` | 0.15 | 0.2 |
| `fase4_node.scan_tolerancia` | 0.03 | 0.05 |
| `fase4_node.takeoff_height` | -1.0 | -0.9 |
| `fase4_node.tolerancia_centro` | 0.08 | 0.06 |
| `fase4_node.yaw_tolerance` | 0.05 | 0.03 |

### teste_yaw

| parametro | simulacao | voo |
|---|---|---|
| `teste_yaw_node.distancia_avanco` | 2.0 | 1.5 |

### mission_1

| parametro | simulacao | voo |
|---|---|---|
| `mission_1_node.aruco_spiral_arc_step` | — | 0.5 |
| `mission_1_node.takeoff_height` | -2.0 | -1.5 |
| `mission_1_node.z_max_search` | -2.0 | -1.5 |

### mission_1_H

| parametro | simulacao | voo |
|---|---|---|
| `mission_1_H_node.aruco_spiral_arc_step` | — | 0.5 |
| `mission_1_H_node.aruco_spiral_step` | 1.0 | 0.7 |
| `mission_1_H_node.base_align_frames` | 10.0 | — |
| `mission_1_H_node.base_max_miss_ticks` | 60.0 | — |
| `mission_1_H_node.base_tolerance` | 0.1 | 0.12 |
| `mission_1_H_node.distancia_percorrida_perpendicular` | 2.5 | 3.0 |
| `mission_1_H_node.lambda_1` | 0.0 | 0.3 |
| `mission_1_H_node.lambda_2` | 1.2 | 1.8 |
| `mission_1_H_node.lambda_3` | -1.2 | -1.8 |
| `mission_1_H_node.lambda_4` | 0.0 | -0.3 |
| `mission_1_H_node.max_horizontal_velocity` | 1.5 | 0.5 |
| `mission_1_H_node.search_aruco_velocity` | 0.5 | 0.4 |
| `mission_1_H_node.search_base_altitude` | -2.7 | — |
| `mission_1_H_node.takeoff_height` | -2.5 | -1.4 |
| `mission_1_H_node.z_max_search` | -2.5 | -1.4 |

### mission_2

| parametro | simulacao | voo |
|---|---|---|
| `mission_2_node.align_fine_frames` | 8.0 | — |
| `mission_2_node.align_fine_tolerance` | 0.2 | — |
| `mission_2_node.align_kd` | 0.1 | — |
| `mission_2_node.align_kd_y` | 0.13 | 0.1 |
| `mission_2_node.align_kd_yaw` | 0.05 | 0.1 |
| `mission_2_node.align_ki_y` | 0.03 | 0.0 |
| `mission_2_node.align_kp` | 0.4 | — |
| `mission_2_node.align_kp_yaw` | 1.0 | 0.5 |
| `mission_2_node.align_min_detections` | 8.0 | — |
| `mission_2_node.align_tolerance_y` | 0.2 | 0.1 |
| `mission_2_node.align_tolerance_yaw` | 0.15 | 0.05 |
| `mission_2_node.align_translate_frames` | 5.0 | — |
| `mission_2_node.align_translate_tolerance` | 0.25 | — |
| `mission_2_node.align_yaw_frames` | 3.0 | — |
| `mission_2_node.ball_approach_velocity` | 0.5 | 0.12 |
| `mission_2_node.ball_cam_scale` | 0.7 | — |
| `mission_2_node.ball_centering_miss_tol` | 10.0 | 5.0 |
| `mission_2_node.ball_confirm_frames` | 1.0 | 3.0 |
| `mission_2_node.ball_diameter_m` | 0.25 | — |
| `mission_2_node.ball_kd_x` | 0.5 | 0.1 |
| `mission_2_node.ball_lookat_max_yaw_step` | 0.07 | 0.12 |
| `mission_2_node.ball_lookat_yaw_kp` | 0.2 | 0.45 |
| `mission_2_node.ball_lost_frames` | 15.0 | — |
| `mission_2_node.ball_miss_frames` | 15.0 | 10.0 |
| `mission_2_node.ball_resize_width` | 600.0 | — |
| `mission_2_node.ball_trigger_score` | 12000.0 | 18000.0 |
| `mission_2_node.hover_before_landing_ticks` | 40.0 | — |
| `mission_2_node.max_horizontal_velocity_align` | 0.2 | — |
| `mission_2_node.max_vel_goto` | 0.5 | — |
| `mission_2_node.rise_target_z` | -2.0 | -2.8 |
| `mission_2_node.rise_timeout_s` | 12.0 | — |
| `mission_2_node.search_radius` | 1.0 | 3.0 |
| `mission_2_node.search_speed` | 0.2 | 0.5 |
| `mission_2_node.takeoff_height` | -1.5 | -2.5 |
| `mission_2_node.target_z` | -1.5 | -2.0 |

### mission_3

| parametro | simulacao | voo |
|---|---|---|
| `fase_3_node.align_kd` | 0.09 | 0.07 |
| `fase_3_node.approach_settle_ticks` | 40.0 | — |
| `fase_3_node.manometer_approach_altitude` | -2.0 | -1.9 |
| `fase_3_node.max_horizontal_velocity_align` | 0.25 | 0.3 |
| `fase_3_node.position_tolerance_align` | 0.12 | 0.1 |
| `fase_3_node.x1` | -6.2 | 2.5 |
| `fase_3_node.x3` | 5.0 | -1.2 |
| `fase_3_node.y1` | -2.0 | 0.0 |
| `fase_3_node.y3` | -2.5 | -2.0 |
| `fase_3_node.z1` | -2.2 | -1.6 |
| `fase_3_node.z2` | -2.2 | -1.6 |
| `fase_3_node.z3` | -2.2 | -1.6 |
| `manometro_detector.angle_at_0` | 240.0 | 90.0 |
| `manometro_detector.angle_at_100` | -60.0 | -70.0 |
| `manometro_detector.rotation_correction_deg` | 0.0 | 180.0 |

### mission_teste

| parametro | simulacao | voo |
|---|---|---|
| `teste_node.align_frames` | 10.0 | 15.0 |
| `teste_node.align_timeout` | 30.0 | 40.0 |
| `teste_node.base_kp_x` | 0.7 | 0.5 |
| `teste_node.base_kp_y` | 0.7 | 0.5 |
| `teste_node.base_max_velocity` | 0.3 | 0.2 |
| `teste_node.base_tolerance` | 0.1 | 0.12 |
| `teste_node.landing_timeout` | 5.0 | 8.0 |
| `teste_node.landing_velocity_max` | 0.5 | 0.3 |
| `teste_node.landing_velocity_min` | 0.15 | 0.1 |
| `teste_node.max_horizontal_velocity` | 0.5 | 0.4 |
| `teste_node.max_vertical_velocity` | 1.2 | 0.8 |
| `teste_node.position_tolerance` | 0.15 | 0.2 |
| `teste_node.position_tolerance_mov` | 0.15 | 0.2 |
| `teste_node.takeoff_height` | -2.0 | -1.5 |
| `teste_node.z` | -2.0 | -1.5 |

## Camera, intrinsecos e ROI

| arquivo:linha | declaracao |
|---|---|
| [src/camera_publisher/camera_publisher/imx_219.py:11](src/camera_publisher/camera_publisher/imx_219.py#L11) | `capture_width=1920,` |
| [src/camera_publisher/camera_publisher/imx_219.py:12](src/camera_publisher/camera_publisher/imx_219.py#L12) | `capture_height=1080,` |
| [src/camera_publisher/camera_publisher/roi_stream.py:42](src/camera_publisher/camera_publisher/roi_stream.py#L42) | `do drone. Por isso 'roi_x'/'roi_y' valem -1 (centrado) por padrao: descentralize` |
| [src/camera_publisher/camera_publisher/roi_stream.py:98](src/camera_publisher/camera_publisher/roi_stream.py#L98) | `self.roi_w = int(self.get_parameter('roi_width').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:99](src/camera_publisher/camera_publisher/roi_stream.py#L99) | `self.roi_h = int(self.get_parameter('roi_height').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:100](src/camera_publisher/camera_publisher/roi_stream.py#L100) | `self.roi_x = int(self.get_parameter('roi_x').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:101](src/camera_publisher/camera_publisher/roi_stream.py#L101) | `self.roi_y = int(self.get_parameter('roi_y').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:102](src/camera_publisher/camera_publisher/roi_stream.py#L102) | `self.out_w = int(self.get_parameter('output_width').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:103](src/camera_publisher/camera_publisher/roi_stream.py#L103) | `self.out_h = int(self.get_parameter('output_height').value)` |
| [src/camera_publisher/camera_publisher/roi_stream.py:187](src/camera_publisher/camera_publisher/roi_stream.py#L187) | `pedido_x = (w - rw) // 2 if self.roi_x < 0 else self.roi_x` |
| [src/camera_publisher/camera_publisher/roi_stream.py:188](src/camera_publisher/camera_publisher/roi_stream.py#L188) | `pedido_y = (h - rh) // 2 if self.roi_y < 0 else self.roi_y` |
| [src/camera_publisher/camera_publisher/webcam_publisher.py:40](src/camera_publisher/camera_publisher/webcam_publisher.py#L40) | `self.frame_width = int(self.get_parameter('frame_width').value)` |
| [src/camera_publisher/camera_publisher/webcam_publisher.py:41](src/camera_publisher/camera_publisher/webcam_publisher.py#L41) | `self.frame_height = int(self.get_parameter('frame_height').value)` |
| [src/camera_publisher/camera_publisher/webcam_publisher.py:74](src/camera_publisher/camera_publisher/webcam_publisher.py#L74) | `f"Camera config: size={self.frame_width}x{self.frame_height} "` |
| [src/camera_publisher/camera_publisher/webcam_publisher.py:95](src/camera_publisher/camera_publisher/webcam_publisher.py#L95) | `frame_resized = cv2.resize(frame_cropped, (self.frame_width, self.frame_height))` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:178](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L178) | `const double fx = this->get_parameter("camera_fx").as_double();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:179](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L179) | `const int width = this->get_parameter("camera_width").as_int();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:180](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L180) | `const int height = this->get_parameter("camera_height").as_int();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:186](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L186) | `calib.fy = this->get_parameter("camera_fy").as_double();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:187](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L187) | `calib.cx = this->get_parameter("camera_cx").as_double();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:188](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L188) | `calib.cy = this->get_parameter("camera_cy").as_double();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:189](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L189) | `calib.image_width = width;` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:190](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L190) | `calib.image_height = height;` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:196](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L196) | `int published = this->get_parameter("published_size").as_int();` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:203](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L203) | `"camera_fx nao informado: intrinsecos derivados do FOV (fx=%.1f, %dx%d)",` |
| [src/cbr2026/fase1/include/fase1/vision_fase1.hpp:209](src/cbr2026/fase1/include/fase1/vision_fase1.hpp#L209) | `calib.yaw = this->get_parameter("camera_yaw").as_double();` |
| [src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py:142](src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py#L142) | `resize_width = int(self.get_parameter('resize_width').value)` |
| [src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py:143](src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py#L143) | `scale = resize_width / float(frame.shape[1])` |
| [src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py:144](src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py#L144) | `frame = cv2.resize(frame, (resize_width, int(frame.shape[0] * scale)))` |
| [src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py:150](src/cv_nodes/ball_detector/ball_detector/ball_detector_node.py#L150) | `r = int(self.get_parameter('roi_margin').value)` |
| [src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py:223](src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py#L223) | `resize_width = int(self.get_parameter('resize_width').value)` |
| [src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py:224](src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py#L224) | `scale = resize_width / float(frame.shape[1])` |
| [src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py:225](src/cv_nodes/mangueira_detector/mangueira_detector/mangueira_detector_node.py#L225) | `frame = cv2.resize(frame, (resize_width, int(frame.shape[0] * scale)))` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:153](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L153) | `published_size <= 0)` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:159](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L159) | `c.image_width = published_size;` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:160](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L160) | `c.image_height = published_size;` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:172](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L172) | `const double scale = static_cast<double>(published_size) / static_cast<double>(crop);` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:222](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L222) | `if (calib_.image_width <= 0 \|\| calib_.image_height <= 0) {` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:453](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L453) | `cx + meia_extensao_x >= calib_.image_width - margem \|\|` |
| [src/vision_geometry/include/vision_geometry/ground_projector.hpp:454](src/vision_geometry/include/vision_geometry/ground_projector.hpp#L454) | `cy + meia_extensao_y >= calib_.image_height - margem;` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:153](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L153) | `published_size <= 0)` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:159](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L159) | `c.image_width = published_size;` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:160](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L160) | `c.image_height = published_size;` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:172](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L172) | `const double scale = static_cast<double>(published_size) / static_cast<double>(crop);` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:192](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L192) | `if (calib_.image_width <= 0 \|\| calib_.image_height <= 0) {` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:423](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L423) | `cx + meia_extensao_x >= calib_.image_width - margem \|\|` |
| [src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp:424](src/vision_geometry/install/vision_geometry/include/vision_geometry/ground_projector.hpp#L424) | `cy + meia_extensao_y >= calib_.image_height - margem;` |
| [src/vision_geometry/test/test_ground_projector.cpp:42](src/vision_geometry/test/test_ground_projector.cpp#L42) | `c.image_width = 800;` |
| [src/vision_geometry/test/test_ground_projector.cpp:43](src/vision_geometry/test/test_ground_projector.cpp#L43) | `c.image_height = 800;` |
