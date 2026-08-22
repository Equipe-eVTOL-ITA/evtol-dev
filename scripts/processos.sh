#!/usr/bin/env bash
# =============================================================================
# processos.sh — de que uma simulação do eVTOL é feita.
# =============================================================================
#
#   source scripts/processos.sh
#
# Este arquivo é a ÚNICA definição de quais processos compõem uma simulação e
# de como encontrá-los. Quem precisa parar (scripts/parar.sh) e quem precisa
# recusar começar por já haver coisa rodando (os simulate.sh das competições)
# leem daqui.
#
# POR QUE ELE EXISTE
#
# A lista vivia duplicada em dois lugares, escrita à mão nos dois:
#
#     .vscode/tasks.json     pkill -x px4; pkill -f 'gz sim'; pkill -x MicroXRCEAgent
#     src/*/scripts/simulate.sh   pgrep -x px4 ... pgrep -f 'gz sim' ...
#
# As duas cópias concordavam, e as duas estavam incompletas do mesmo jeito:
# nenhuma via a ponte de imagem, os nós da missão, o sim2d, a estação de solo
# nem o rosbag. O efeito prático era "parar tudo" deixar meia simulação de pé,
# e a rodada seguinte herdar nós velhos assinando os mesmos tópicos -- que é
# uma das formas mais confusas de depurar, porque o sistema responde, só que
# com dados de antes.
#
# Uma lista só. Quem quiser um grupo novo, acrescenta aqui.
#
# Feito para ser SOURCED. Não usa `set -e` nem `exit`.
# =============================================================================

# shellcheck shell=bash

_EVTOL_PROC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVTOL_WS_ROOT="$(cd "$_EVTOL_PROC_DIR/.." && pwd)"
export EVTOL_WS_ROOT

# -----------------------------------------------------------------------------
# Os grupos, NA ORDEM EM QUE DEVEM MORRER.
#
# A ordem não é estética. Os nós da missão e o rosbag saem primeiro, com o
# sistema ainda de pé, para que o `ros2 launch` consiga fechar o que abriu --
# em especial o bag, que precisa ser fechado para ganhar índice. Só então cai a
# infraestrutura embaixo deles.
# -----------------------------------------------------------------------------
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
            # próprios. O `-f 'gz sim'` de antes pegava só o wrapper: o servidor
            # e a interface sobreviviam, e a porta e o mundo continuavam presos.
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
            # `ros2 launch` é o pai: um SIGINT nele derruba, de forma ordenada,
            # tudo o que ele subiu -- inclusive o rosbag do ground.launch.py.
            printf 'f\tros2 launch\n'
            # E o modo `w`: todo processo cujo BINÁRIO mora no install/ deste
            # workspace. Ver _evtol_pids_do_workspace.
            printf 'w\t-\n'
            ;;
        *)
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# PIDs vivos de um grupo, um por linha.
#
# O próprio processo que pergunta e seus ancestrais ficam de fora. Sem isso,
# `parar.sh` casaria com a própria linha de comando via `-f` e se mataria no
# meio do trabalho -- deixando de pé justamente o que devia ter matado.
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# A cadeia de ancestrais deste shell, calculada UMA vez.
#
# A versão anterior chamava `ps -o ppid=` por candidato, a cada varredura. Numa
# espera de 9 segundos com poll de 0,25 s isso virava milhares de forks, e o
# `parar.sh` levava 47 s medidos para encerrar dois processos de teste. Um
# script de parada precisa ser mais rápido do que a paciência de quem o roda.
#
# O /proc/PID/stat traz o pai no 4º campo, e lê-se com o `read` embutido do
# bash -- sem processo nenhum.
# -----------------------------------------------------------------------------
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
# POR QUE PELO /proc, E NÃO POR `pgrep -f <caminho>`
#
# A primeira versão casava o caminho absoluto do install/ na linha de comando
# com `pgrep -f`. Parece a mesma coisa e não é: medido aqui, `bash
# install/no.sh` produz uma linha de comando RELATIVA, e o padrão absoluto não
# casa. O bash ainda troca o próprio processo pelo último comando (`exec`), e
# o caminho que estava lá some.
#
# Ler /proc é também o que torna a varredura barata: `read` e `mapfile` são
# embutidos do bash, então percorrer o /proc inteiro não cria processo nenhum.
# A versão com `cat | tr | grep` por PID custava três forks por processo vivo.
#
# Ancorado no caminho ABSOLUTO deste workspace, um outro workspace ROS na mesma
# máquina nunca casa por engano.
# -----------------------------------------------------------------------------
_evtol_pids_do_workspace() {
    local prefixo="$EVTOL_WS_ROOT/install/"
    local proc pid alvo
    local -a args

    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"

        # A linha de comando, e não o /proc/PID/exe.
        #
        # O exe seria o binário resolvido pelo kernel, imune a quem reescreve o
        # argv[0] -- mas lê-lo exige `readlink`, que é um fork POR PROCESSO da
        # máquina. Não compensa: tanto `ros2 launch` quanto `ros2 run` passam o
        # caminho ABSOLUTO do install/ como argv[0], então a varredura da linha
        # de comando acha os nós em C++ e os em Python pelo mesmo caminho. E um
        # nó que reescrevesse o próprio argv[0] ainda cairia junto com o
        # `ros2 launch` que o subiu, pelo padrão do grupo.
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

# -----------------------------------------------------------------------------
# Há simulação rodando? Usado pelo guard dos simulate.sh.
#
# Ecoa os grupos ocupados (vazio = nada rodando) e devolve 0 se achou algo.
# -----------------------------------------------------------------------------
evtol_simulacao_viva() {
    local grupo achou=1
    for grupo in px4 gazebo agente; do
        if [[ -n "$(evtol_pids_do_grupo "$grupo")" ]]; then
            echo "$grupo"
            achou=0
        fi
    done
    return $achou
}
