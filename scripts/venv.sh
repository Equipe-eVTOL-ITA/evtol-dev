#!/usr/bin/env bash
# =============================================================================
# venv.sh — cria/atualiza o ambiente Python do workspace, sem tocar no sistema.
# =============================================================================
#
#   ./scripts/venv.sh                    # usa o perfil de .evtol-profile
#   ./scripts/venv.sh --profile jetson-humble
#
# POR QUE EXISTE
#
# Os pacotes pip que o workspace exige colidem com o resto da máquina. O caso
# concreto que motivou isto, medido nesta máquina:
#
#   - o `mediapipe` exige `protobuf < 5`;
#   - o `~/.local` tinha `protobuf 7.34.1`, posto lá pelo `tensorboard`, que
#     por sua vez exige `>= 6.31.1`.
#
# Não há versão que satisfaça os dois. Instalar o mediapipe no sistema
# rebaixaria o protobuf e quebraria ferramentas que não têm nada a ver com o
# drone. Verificado que o limite do mediapipe é REAL e não conservador: com o
# protobuf 7, `GestureRecognizer.create_from_options` falha com
# `MessageFactory object has no attribute GetPrototype`.
#
# COMO FUNCIONA, e por que não é um venv comum
#
# O venv é criado com `--system-site-packages`, então ele ENXERGA o ROS
# (rclpy, custom_msgs, os pacotes do workspace) sem precisar reinstalá-los.
#
# E ele NÃO é ativado no sentido usual. O `ros_env.sh` apenas põe o
# `site-packages` dele na frente do `PYTHONPATH`. Isso importa: os executáveis
# que o colcon instala têm `#!/usr/bin/python3` gravado no shebang, e ativar um
# venv não muda o interpretador que o `ros2 run` dispara. Mudar o PYTHONPATH
# muda de ONDE esse interpretador importa — que é o que resolve o conflito.
#
# Resultado: `ros2 run` continua usando /usr/bin/python3, mas importa o
# protobuf 4.25 e o opencv-contrib do venv, enquanto o resto da máquina segue
# com o que já tinha.
# =============================================================================

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

profile=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile|-p) profile="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "venv.sh: opção desconhecida: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$profile" ]]; then
    if [[ -f "$ws_root/.evtol-profile" ]]; then
        profile="$(tr -d '[:space:]' < "$ws_root/.evtol-profile")"
    else
        echo "venv.sh: nenhum perfil. Use --profile <nome> ou crie .evtol-profile." >&2
        exit 1
    fi
fi

venv_dir="$ws_root/.venv"

echo "Perfil: $profile"
echo "Venv:   $venv_dir"
echo

if [[ ! -d "$venv_dir" ]]; then
    echo "Criando o venv (com --system-site-packages, para enxergar o ROS)..."
    python3 -m venv --system-site-packages "$venv_dir"
fi

# As versões vêm do perfil, nunca escritas aqui. É o mesmo contrato que o
# doctor confere — se divergissem, um diria que está tudo certo enquanto o
# outro instalava outra coisa.
mapfile -t pacotes < <(python3 "$ws_root/env/doctor.py" --get pip.required --profile "$profile" \
    | python3 -c "
import ast, sys
d = ast.literal_eval(sys.stdin.read().strip())
for nome, ver in d.items():
    print(f'{nome}{ver}' if ver.lstrip()[0] in '<>=!~' else f'{nome}=={ver}')
")

if [[ ${#pacotes[@]} -eq 0 ]]; then
    echo "venv.sh: o perfil '$profile' não declara pip.required." >&2
    exit 1
fi

echo "Instalando o que o perfil exige:"
printf '  %s\n' "${pacotes[@]}"
echo

"$venv_dir/bin/pip" install --quiet --upgrade pip
"$venv_dir/bin/pip" install "${pacotes[@]}"

echo
echo "Pronto. O ros_env.sh já usa este venv automaticamente."
echo "Confira com:  ./doctor.sh"
