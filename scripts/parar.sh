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
# SIGINT primeiro, escalada só para quem ignorar, e relatório do que sobrou.
# Sai com erro se sobrou algo: "parar tudo" não pode terminar em verde com meia
# simulação de pé.
#
# A versão anterior era um pkill seco de três processos, mandava SIGKILL de
# saída (o que deixa o rosbag sem índice) e limpava /tmp/px4* mesmo quando o
# kill falhava.
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
# O `ros2 launch` o intercepta e desliga os nós em ordem; o `ros2 bag record`
# fecha o arquivo. É o único sinal que preserva o trabalho.
echo "Encerrando (SIGINT)..."
for g in $alvos; do
    pids="${antes[$g]}"
    [[ -z "${pids// /}" ]] && continue
    printf '  %-8s %s\n' "$g" "$(wc -w <<< "$pids") processo(s)"
    # shellcheck disable=SC2086
    kill -INT $pids 2>/dev/null
    # Um respiro: o `ros2 launch` precisa repassar o sinal aos filhos.
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
    # Aritmética inteira do bash: `bc` não está instalado na Jetson.
    local restam=$(( $1 * 4 ))
    while (( restam-- > 0 )); do
        [[ -z "$(sobreviventes_de | tr -d ' ')" ]] && return 0
        sleep 0.25
    done
    [[ -z "$(sobreviventes_de | tr -d ' ')" ]]
}

# 6 s: o suficiente para um bag grande escrever o índice.
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
        # Um bag levado a KILL fica sem índice; quem gravava precisa saber.
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
