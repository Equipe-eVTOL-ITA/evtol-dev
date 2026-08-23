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
# O alvo é o nome do pacote, e pronto. Os build.sh das competições só aceitam
# pacotes da própria competição -- deixando de fora camera_publisher, cv_nodes,
# drone_lib e stdstates -- e o `all` deles significa o workspace inteiro em
# todos, o que tornava o prefixo da competição irrelevante.
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
if [[ "$modo" == "changed" ]]; then
    modo="--packages-select"
    alvos=()
    # Só os repositórios DO MANIFESTO: o legado em src/ (itajuba, sae_2025,
    # cm204-evtol) vive permanentemente sujo.
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

    # Valida ANTES de compilar: com --packages-select, um nome errado faz o
    # colcon não compilar nada e sair com sucesso.
    disponiveis="$(pacotes_do_workspace)"
    invalidos=()
    for alvo in "${alvos[@]}"; do
        grep -qx -- "$alvo" <<< "$disponiveis" || invalidos+=("$alvo")
    done

    if [[ ${#invalidos[@]} -gt 0 ]]; then
        for alvo in "${invalidos[@]}"; do
            echo "build.sh: não existe pacote '$alvo'." >&2
            # Prefixos cada vez mais curtos: um grep pelo nome inteiro não
            # acha nada quando o erro é uma letra ("camera_publishr").
            perto=""
            for (( n=${#alvo}; n >= 3; n-- )); do
                # `|| true`: sob `set -e`, um grep vazio abortaria aqui.
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
