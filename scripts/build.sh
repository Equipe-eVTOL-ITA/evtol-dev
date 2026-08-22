#!/usr/bin/env bash
# =============================================================================
# build.sh — compila o que você pedir, de qualquer lugar do workspace.
# =============================================================================
#
#   ./scripts/build.sh camera_publisher cv_nodes   um ou vários pacotes
#   ./scripts/build.sh --select cv_nodes           só ele, sem as dependências
#   ./scripts/build.sh --above stdstates           ele e quem depende dele
#   ./scripts/build.sh --all                       o workspace inteiro
#   ./scripts/build.sh --deps                      só as bibliotecas de base
#   ./scripts/build.sh --changed                   os repos com trabalho solto
#   ./scripts/build.sh --lista                     os nomes que ele aceita
#
#   Opções: --debug (build type Debug)   --test (roda os testes ao fim)
#           --continue (não para no primeiro pacote que falhar)
#
# POR QUE ELE EXISTE, se cada competição já tem um build.sh
#
# Os build.sh das competições são bons no que fazem e limitados no resto: cada
# um só aceita pacotes DA SUA competição, e a task do VSCode os chamava com um
# alvo no formato "competicao:pacote". Duas consequências, as duas medidas:
#
#   Não havia como compilar um pacote que não pertence a competição nenhuma --
#   camera_publisher, cv_nodes, drone_lib, stdstates. Justamente os que mais se
#   mexe, e os únicos que quebram todas as missões de uma vez.
#
#   `all` significava "o workspace inteiro" em todos eles. Então cbr2026:all,
#   sae2026:all e ensaio_em_voo:all faziam exatamente a mesma coisa, e a
#   escolha da competição no menu não queria dizer nada.
#
# Aqui o alvo é o nome do pacote, e pronto. A competição não entra na conta
# porque nunca fez diferença.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

# Nunca escreva `source /opt/ros/humble/setup.bash` aqui: voamos com Humble na
# Jetson e Jazzy na Raspberry, e o mesmo script serve aos dois.
# shellcheck source=scripts/ros_env.sh
source "$ws_root/scripts/ros_env.sh"

cd "$ws_root"

# --executor sequential evita picos de RAM (veja docs/SETUP.md, seção de swap).
BUILD_TYPE=RelWithDebInfo
modo="--packages-up-to"
alvos=()
rodar_teste=0
extra=()

# As bibliotecas de base: o que todo mundo usa e quase ninguém lembra de
# recompilar depois de um `vcs import` ou de um bump de pin.
DEPS=(stdstates stdbt drone_lib fsm custom_msgs vision_geometry maze_geometry)

pacotes_do_workspace() {
    colcon list --names-only --base-paths src 2>/dev/null | sort -u
}

uso() {
    sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=\+$'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --select|-s)   modo="--packages-select"; shift ;;
        --above|-a)    modo="--packages-above"; shift ;;
        --up-to|-u)    modo="--packages-up-to"; shift ;;
        --all)         modo="all"; shift ;;
        --deps)        modo="--packages-up-to"; alvos+=("${DEPS[@]}"); shift ;;
        --changed)     modo="changed"; shift ;;
        --debug)       BUILD_TYPE=Debug; shift ;;
        --test)        rodar_teste=1; shift ;;
        --continue)    extra+=(--continue-on-error); shift ;;
        --lista|-l)    pacotes_do_workspace; exit 0 ;;
        -h|--help)     uso; exit 0 ;;
        -*)            echo "build.sh: opção desconhecida: $1" >&2; uso >&2; exit 2 ;;
        *)             alvos+=("$1"); shift ;;
    esac
done

COMMON=(--symlink-install --executor sequential
        --cmake-args "-DCMAKE_BUILD_TYPE=$BUILD_TYPE" "-DCMAKE_EXPORT_COMPILE_COMMANDS=On"
        "${extra[@]+"${extra[@]}"}")

# --changed: os pacotes cujo repositório tem trabalho solto.
#
# É o alvo do dia a dia -- "compile o que eu mexi" -- e evita tanto o
# `--all` de cinco minutos quanto a lista digitada à mão que sempre esquece um.
if [[ "$modo" == "changed" ]]; then
    modo="--packages-select"
    alvos=()
    # Só os repositórios DO MANIFESTO.
    #
    # src/ também guarda trabalho legado que não está no evtol.repos --
    # itajuba, sae_2025, cm204-evtol. Eles vivem permanentemente "sujos", e
    # incluí-los fazia o --changed propor 12 pacotes quando dois tinham mudado.
    while IFS= read -r repo; do
        repo="src/$repo"
        [[ -d "$repo/.git" ]] || continue
        [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]] || continue
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && alvos+=("$pkg")
        done < <(colcon list --names-only --base-paths "$repo" 2>/dev/null)
    done < <(python3 -c "
import yaml
for nome in yaml.safe_load(open('evtol.repos'))['repositories']:
    print(nome)
")

    if [[ ${#alvos[@]} -eq 0 ]]; then
        echo "Nenhum repositório de src/ tem trabalho solto. Nada a compilar."
        exit 0
    fi
    echo "Repositórios com trabalho solto -> ${#alvos[@]} pacote(s):"
    printf '    %s\n' "${alvos[@]}"
    echo
fi

if [[ "$modo" == "all" ]]; then
    echo "Compilando o workspace inteiro ($BUILD_TYPE)..."
    colcon build "${COMMON[@]}"
else
    if [[ ${#alvos[@]} -eq 0 ]]; then
        echo "build.sh: diga o que compilar." >&2
        echo >&2
        uso >&2
        exit 2
    fi

    # Valida ANTES de compilar. Um nome errado que só aparece depois de o
    # colcon rodar custa a espera inteira para nada -- e o colcon, com
    # --packages-select, simplesmente não compila nada e sai com sucesso.
    disponiveis="$(pacotes_do_workspace)"
    invalidos=()
    for alvo in "${alvos[@]}"; do
        grep -qx -- "$alvo" <<< "$disponiveis" || invalidos+=("$alvo")
    done

    if [[ ${#invalidos[@]} -gt 0 ]]; then
        for alvo in "${invalidos[@]}"; do
            echo "build.sh: não existe pacote '$alvo'." >&2
            # Sugere pelos nomes que contêm o que foi digitado, e vice-versa.
            # Erro de digitação em nome de pacote é comum o bastante para que
            # recusar sem ajudar seja gasto de tempo de alguém.
            # Prefixos cada vez mais curtos do que foi digitado. Um `grep`
            # pelo nome inteiro não acha nada quando o erro é justamente uma
            # letra ("camera_publishr"), que é o caso comum -- e recusar sem
            # ajudar gasta o tempo de quem digitou.
            perto=""
            for (( n=${#alvo}; n >= 3; n-- )); do
                # O `|| true` não é decoração: sob `set -e`, um grep que não
                # acha nada devolve 1 e abortaria o script AQUI -- no meio da
                # mensagem de erro, sem nunca chegar à sugestão.
                perto="$(grep -i -- "^${alvo:0:n}" <<< "$disponiveis" | head -5 || true)"
                [[ -n "$perto" ]] && break
            done
            if [[ -n "$perto" ]]; then
                echo "          Você quis dizer:" >&2
                sed 's/^/            /' <<< "$perto" >&2
            fi
        done
        echo >&2
        echo "          A lista inteira: ./scripts/build.sh --lista" >&2
        exit 1
    fi

    echo "Compilando ($BUILD_TYPE, ${modo#--packages-}): ${alvos[*]}"
    colcon build "${COMMON[@]}" "$modo" "${alvos[@]}"
fi

if (( rodar_teste )); then
    echo
    echo "Rodando os testes..."
    if [[ "$modo" == "all" ]]; then
        colcon test --executor sequential
    else
        colcon test --executor sequential --packages-select "${alvos[@]}"
    fi
    colcon test-result --verbose
fi

echo
echo "Pronto. Em cada shell novo, a partir de $ws_root:"
echo "    source scripts/ros_env.sh"
