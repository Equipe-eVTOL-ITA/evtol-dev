#!/usr/bin/env bash
# =============================================================================
# parar.sh — encerra a simulação inteira, e confere que encerrou.
# =============================================================================
#
#   ./scripts/parar.sh                 tudo
#   ./scripts/parar.sh sim             só a simulação (px4, gazebo, agente, ponte)
#   ./scripts/parar.sh --so bag,ponte  só os grupos listados
#   ./scripts/parar.sh --lista         não mata nada; só mostra o que está vivo
#
# POR QUE ELE NÃO É UMA LINHA DE pkill
#
# A versão anterior era, e tinha três defeitos que só apareciam depois:
#
#   1. Matava px4, `gz sim` e o agente, e mais nada. A ponte de imagem, os nós
#      da missão, o sim2d, a estação de solo e o rosbag continuavam de pé. A
#      rodada seguinte subia por cima deles, com dois publicadores no mesmo
#      tópico -- o sistema responde, com dados de antes, e ninguém desconfia.
#
#   2. Mandava SIGKILL de saída. Um `ros2 bag record` morto a KILL não fecha o
#      arquivo, e um bag sem índice não abre no `ros2 bag info`. O bag da fase3
#      É o registro do voo: perdê-lo é perder a razão de ter voado.
#
#   3. Rodava `rm -rf /tmp/px4*` incondicionalmente, mesmo quando o pkill tinha
#      falhado -- apagando o estado de um PX4 que continuava vivo.
#
# Aqui: SIGINT primeiro (que é o que o ROS entende por "termine o que está
# fazendo"), escalada só para quem ignorar, e um relatório do que sobrou. Se
# sobrou algo, o script sai com erro -- "parar tudo" não pode terminar em verde
# com meia simulação de pé.
# =============================================================================
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/processos.sh
source "$script_dir/processos.sh"

# ── Argumentos ───────────────────────────────────────────────────────────────
GRUPOS_SIM="ponte agente gazebo px4"
alvos=""
so_listar=0

uso() {
    sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=\+$'
    echo
    echo "Grupos:"
    local g
    for g in $(evtol_grupos); do
        printf '  %-8s %s\n' "$g" "$(evtol_descricao_grupo "$g")"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        tudo)      alvos="$(evtol_grupos | tr '\n' ' ')"; shift ;;
        sim)       alvos="$GRUPOS_SIM"; shift ;;
        --so)      alvos="${2:-}"; alvos="${alvos//,/ }"; shift 2 ;;
        --lista|-l) so_listar=1; shift ;;
        -h|--help) uso; exit 0 ;;
        *)         echo "parar.sh: argumento desconhecido: $1" >&2; uso >&2; exit 2 ;;
    esac
done

[[ -z "$alvos" ]] && alvos="$(evtol_grupos | tr '\n' ' ')"

# Valida os grupos ANTES de sinalizar qualquer coisa. Um nome errado em `--so`
# não pode virar "não matou nada e disse que estava tudo certo".
for g in $alvos; do
    if ! evtol_padroes "$g" >/dev/null 2>&1; then
        echo "parar.sh: grupo desconhecido: '$g'" >&2
        echo "          Grupos: $(evtol_grupos | tr '\n' ' ')" >&2
        exit 2
    fi
done

# Reordena os alvos na ordem canônica de morte (nós e bag primeiro).
ordenados=""
for g in $(evtol_grupos); do
    for a in $alvos; do
        [[ "$g" == "$a" ]] && ordenados+="$g "
    done
done
alvos="$ordenados"

# ── Levantamento inicial ─────────────────────────────────────────────────────
declare -A antes
total_antes=0
for g in $alvos; do
    pids="$(evtol_pids_do_grupo "$g" | tr '\n' ' ')"
    antes["$g"]="$pids"
    n=$(wc -w <<< "$pids")
    total_antes=$(( total_antes + n ))
done

if (( so_listar )); then
    echo "Processos vivos:"
    vazio=1
    for g in $alvos; do
        for pid in ${antes[$g]}; do
            printf '  %-8s %-6s %s\n' "$g" "$pid" "$(evtol_nome_do_pid "$pid")"
            vazio=0
        done
    done
    (( vazio )) && echo "  (nenhum)"
    exit 0
fi

if (( total_antes == 0 )); then
    echo "Nada para parar."
    exit 0
fi

# ── Fase 1: SIGINT, na ordem ─────────────────────────────────────────────────
#
# SIGINT é o Ctrl+C. O `ros2 launch` o intercepta e desliga os nós que subiu na
# ordem certa; o `ros2 bag record` o intercepta e FECHA o arquivo. É o único
# sinal que preserva o trabalho.
echo "Encerrando (SIGINT)..."
for g in $alvos; do
    pids="${antes[$g]}"
    [[ -z "${pids// /}" ]] && continue
    printf '  %-8s %s\n' "$g" "$(wc -w <<< "$pids") processo(s)"
    # shellcheck disable=SC2086
    kill -INT $pids 2>/dev/null
    # Um respiro entre grupos: o `ros2 launch` precisa de um instante para
    # repassar o sinal aos filhos antes de a infraestrutura sumir embaixo dele.
    sleep 0.3
done

sobreviventes_de() {
    local g saida=""
    for g in $alvos; do
        saida+="$(evtol_pids_do_grupo "$g" | tr '\n' ' ')"
    done
    echo "$saida"
}

esperar_ate() {
    # esperar_ate <segundos>; devolve 0 se tudo morreu dentro do prazo.
    #
    # Conta em quartos de segundo com aritmética inteira do próprio bash. Sem
    # `bc`: ele não está instalado na Jetson, e um script de parada não pode
    # depender de pacote que a máquina de voo talvez não tenha.
    local restam=$(( $1 * 4 ))
    while (( restam-- > 0 )); do
        [[ -z "$(sobreviventes_de | tr -d ' ')" ]] && return 0
        sleep 0.25
    done
    [[ -z "$(sobreviventes_de | tr -d ' ')" ]]
}

# 6 s: o suficiente para um `ros2 bag record` grande terminar de escrever o
# índice. Abaixo disso já se viu bag truncado.
if ! esperar_ate 6; then
    restantes="$(sobreviventes_de)"
    if [[ -n "${restantes// /}" ]]; then
        echo "Insistindo (SIGTERM) em $(wc -w <<< "$restantes") processo(s)..."
        # shellcheck disable=SC2086
        kill -TERM $restantes 2>/dev/null
        esperar_ate 3 || true
    fi
fi

restantes="$(sobreviventes_de)"
if [[ -n "${restantes// /}" ]]; then
    echo "Forçando (SIGKILL) em $(wc -w <<< "$restantes") processo(s)..."
    for pid in $restantes; do
        nome="$(evtol_nome_do_pid "$pid")"
        # Um bag levado a KILL fica sem índice. Avisar é o mínimo: quem estava
        # gravando um voo precisa saber que o arquivo pode não abrir.
        [[ "$nome" == *bag* ]] && \
            echo "  AVISO: o rosbag ($pid) não respondeu ao SIGINT. O arquivo pode ficar sem índice." >&2
    done
    # shellcheck disable=SC2086
    kill -KILL $restantes 2>/dev/null
    sleep 1
fi

# ── Limpeza do /tmp, SÓ se o px4 realmente morreu ────────────────────────────
if [[ " $alvos " == *" px4 "* ]]; then
    if [[ -z "$(evtol_pids_do_grupo px4)" ]]; then
        rm -rf /tmp/px4* 2>/dev/null
    else
        echo "  /tmp/px4* preservado: ainda há PX4 vivo." >&2
    fi
fi

# ── Relatório ────────────────────────────────────────────────────────────────
echo
printf '%-8s %6s %6s\n' "grupo" "antes" "agora"
falhou=0
for g in $alvos; do
    n_antes=$(wc -w <<< "${antes[$g]}")
    agora="$(evtol_pids_do_grupo "$g" | tr '\n' ' ')"
    n_agora=$(wc -w <<< "$agora")
    (( n_antes == 0 && n_agora == 0 )) && continue
    marca="ok"
    if (( n_agora > 0 )); then
        marca="SOBROU"
        falhou=1
    fi
    printf '%-8s %6s %6s  %s\n' "$g" "$n_antes" "$n_agora" "$marca"
    for pid in $agora; do
        printf '         %6s  %s\n' "$pid" "$(evtol_nome_do_pid "$pid")"
    done
done

if (( falhou )); then
    echo
    echo "Sobrou processo de pé. Veja quem é com:" >&2
    echo "    ./scripts/parar.sh --lista" >&2
    exit 1
fi

echo
echo "simulação encerrada"
