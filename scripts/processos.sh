#!/usr/bin/env bash
# =============================================================================
# processos.sh — de que uma simulação do eVTOL é feita.
# =============================================================================
#
#   source scripts/processos.sh
#
# A ÚNICA definição de quais processos compõem uma simulação. Lida pelo
# parar.sh e pelos simulate.sh das competições, que antes mantinham cada um a
# sua cópia da lista — as duas incompletas do mesmo jeito.
#
# Feito para ser SOURCED. Não usa `set -e` nem `exit`.
# =============================================================================

# shellcheck shell=bash

_EVTOL_PROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVTOL_WS_ROOT="$(cd "$_EVTOL_PROC_DIR/.." && pwd)"
export EVTOL_WS_ROOT

# Os grupos, NA ORDEM EM QUE DEVEM MORRER: os nós e o bag primeiro, com o
# sistema ainda de pé, para que o `ros2 launch` feche o que abriu -- em
# especial o bag, que sem isso fica sem índice.
evtol_grupos() {
    printf '%s\n' nos bag ponte agente gazebo px4
}

evtol_descricao_grupo() {
    case "$1" in
        nos)    echo "nós deste workspace (missão, sim2d, estação de solo, detectores)" ;;
        bag)    echo "gravação em rosbag" ;;
        ponte)  echo "ponte de imagem Gazebo→ROS" ;;
        agente) echo "agente Micro-XRCE-DDS" ;;
        gazebo) echo "Gazebo (servidor e interface)" ;;
        px4)    echo "PX4 SITL" ;;
        *)      echo "(grupo desconhecido)" ;;
    esac
}

# -----------------------------------------------------------------------------
# Os padrões de cada grupo, um por linha, como "<modo><TAB><padrão>".
#
#   x  casa o NOME do executável, exato       (pgrep -x / pkill -x)
#   f  casa a linha de comando inteira        (pgrep -f / pkill -f)
#   w  todo processo que roda a partir do install/ deste workspace; o padrão
#      é ignorado (ver _evtol_pids_do_workspace)
# -----------------------------------------------------------------------------
evtol_padroes() {
    case "$1" in
        px4)
            printf 'x\tpx4\n'
            ;;
        gazebo)
            # `gz sim` é um wrapper em ruby que exec'a dois binários com nomes
            # próprios; casar só o wrapper deixava servidor e interface vivos.
            printf 'f\tgz sim\n'
            printf 'x\tgz-sim-server\n'
            printf 'x\tgz-sim-gui\n'
            ;;
        agente)
            printf 'x\tMicroXRCEAgent\n'
            ;;
        ponte)
            printf 'f\tros_gz_image\n'
            printf 'x\timage_bridge\n'
            printf 'f\tros_gz_bridge\n'
            printf 'x\tparameter_bridge\n'
            ;;
        bag)
            printf 'f\tros2 bag record\n'
            ;;
        nos)
            # `ros2 launch` é o pai: um SIGINT nele derruba o que ele subiu,
            # inclusive o rosbag. O modo `w` pega o resto.
            printf 'f\tros2 launch\n'
            printf 'w\t-\n'
            ;;
        *)
            return 1
            ;;
    esac
}

# PIDs vivos de um grupo. O próprio processo e seus ancestrais ficam de fora:
# senão o parar.sh casaria com a própria linha de comando e se mataria.
evtol_pids_do_grupo() {
    local grupo="$1" modo padrao encontrados=""

    while IFS=$'\t' read -r modo padrao; do
        [[ -z "$modo" ]] && continue
        case "$modo" in
            x) encontrados+=" $(pgrep -x -- "$padrao" 2>/dev/null | tr '\n' ' ')" ;;
            w) encontrados+=" $(_evtol_pids_do_workspace | tr '\n' ' ')" ;;
            *) encontrados+=" $(pgrep -f -- "$padrao" 2>/dev/null | tr '\n' ' ')" ;;
        esac
    done < <(evtol_padroes "$grupo")

    _evtol_carregar_ancestrais

    local pid
    for pid in $encontrados; do
        [[ " $_EVTOL_ANCESTRAIS " == *" $pid "* ]] && continue
        echo "$pid"
    done | sort -un
}

# A cadeia de ancestrais deste shell, calculada UMA vez e lida do /proc com o
# `read` embutido. Com um `ps` por candidato a cada varredura, o parar.sh
# levava 47 s medidos para encerrar dois processos.
_EVTOL_ANCESTRAIS=""
_evtol_carregar_ancestrais() {
    [[ -n "$_EVTOL_ANCESTRAIS" ]] && return 0

    local atual="$$" campos resto
    while [[ -n "$atual" && "$atual" != "0" ]]; do
        _EVTOL_ANCESTRAIS+="$atual "
        [[ "$atual" == "1" ]] && break
        [[ -r "/proc/$atual/stat" ]] || break
        # O comando do processo vai entre parênteses e pode conter espaços, o
        # que estraga a contagem de campos. Cortar depois do ')' resolve: o que
        # sobra é "<estado> <ppid> ...".
        read -r campos < "/proc/$atual/stat" || break
        resto="${campos#*) }"
        atual="${resto#* }"
        atual="${atual%% *}"
    done
}

# -----------------------------------------------------------------------------
# Todo processo que roda a partir do install/ deste workspace.
#
# Lido do /proc com embutidos do bash: sem fork por PID, e imune a linha de
# comando relativa (que `pgrep -f <caminho absoluto>` não casa). Ancorado no
# caminho absoluto, outro workspace ROS na mesma máquina nunca casa por engano.
_evtol_pids_do_workspace() {
    local prefixo="$EVTOL_WS_ROOT/install/"
    local proc pid alvo
    local -a args

    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"

        # A linha de comando, e não o /proc/PID/exe: ler o exe exigiria um
        # `readlink` por processo da máquina, e tanto `ros2 launch` quanto
        # `ros2 run` já passam o caminho absoluto do install/ como argv[0].
        [[ -r "$proc/cmdline" ]] || continue
        args=()
        mapfile -d '' -t args < "$proc/cmdline" 2>/dev/null || continue
        for alvo in "${args[@]}"; do
            if [[ "$alvo" == "$prefixo"* ]]; then
                echo "$pid"
                break
            fi
        done
    done
}

# Nome legível de um PID, para as mensagens. Lê o /proc: sem fork.
evtol_nome_do_pid() {
    local nome=""
    [[ -r "/proc/$1/comm" ]] && read -r nome < "/proc/$1/comm"
    echo "${nome:-?}"
}

# Há simulação rodando?  evtol_simulacao_viva [grupo...]  (padrão: px4 gazebo)
# Ecoa os grupos ocupados e devolve 0 se achou algo.
#
# O AGENTE NÃO ESTÁ NO PADRÃO de propósito: o VS Code roda as tasks de um
# `dependsOn` em paralelo, e o agente recém-nascido fazia o guard do
# simulate.sh recusar a própria task. Cada script guarda o que ele mesmo
# inicia; a checagem do agente está no agent.sh.
evtol_simulacao_viva() {
    local grupos=("$@")
    [[ ${#grupos[@]} -eq 0 ]] && grupos=(px4 gazebo)

    local grupo achou=1
    for grupo in "${grupos[@]}"; do
        if [[ -n "$(evtol_pids_do_grupo "$grupo")" ]]; then
            echo "$grupo"
            achou=0
        fi
    done
    return $achou
}
