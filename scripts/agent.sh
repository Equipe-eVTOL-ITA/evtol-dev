#!/usr/bin/env bash
# =============================================================================
# agent.sh — sobe o Micro XRCE-DDS Agent, a ponte entre o PX4 e o ROS 2.
# =============================================================================
#
#   ./scripts/agent.sh                    simulação: UDP na porta 8888
#   ./scripts/agent.sh --serial           voo: serial, com os padrões da Jetson
#   ./scripts/agent.sh --serial /dev/ttyUSB0 57600
#   ./scripts/agent.sh --porta 8889       outra porta UDP
#
# POR QUE ESTE ARQUIVO ESTÁ NA RAIZ, e não em cada competição
#
# Havia um agent.sh por competição -- cbr2026, sae2026, e o do templates/ --
# e os três eram byte a byte o mesmo arquivo. A task do VSCode chegou a
# perguntar QUAL MUNDO você queria só para decidir de qual competição pegar um
# script idêntico ao das outras; era essa pergunta que aparecia duas vezes ao
# subir uma missão.
#
# Um agente só, e a pergunta some.
#
# O MODO SERIAL, que faltava
#
# Em simulação o agente fala UDP. Em voo NÃO: o Pixhawk está ligado por fio.
# Os agent.sh das competições só sabiam UDP, e o comando de voo vivia solto
# num comentário e repetido no docs/VOO_SSH.md -- para ser digitado à mão, por
# SSH, com o drone armado esperando. É o tipo de coisa que se digita errado
# uma vez só.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

# shellcheck source=scripts/ros_env.sh
source "$ws_root/scripts/ros_env.sh"

# O agente é compilado à mão e instalado no /usr/local/bin, que não está no
# PATH de todo shell não interativo.
export PATH="$PATH:/usr/local/bin"

modo="udp"
porta=8888
# Na Jetson o Pixhawk costuma aparecer no ttyTHS1; confirme com `ls /dev/tty*`
# com e sem o cabo. 921600 é o baud que o PX4 usa no UART do companion.
dispositivo="/dev/ttyTHS1"
baud=921600

uso() { sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=\+$'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --serial)
            modo="serial"; shift
            # Os dois seguintes são opcionais e posicionais. Só consome o que
            # não começa com '-', para que `--serial --porta 9` não engula a
            # flag seguinte como se fosse um dispositivo.
            [[ $# -gt 0 && "$1" != -* ]] && { dispositivo="$1"; shift; }
            [[ $# -gt 0 && "$1" != -* ]] && { baud="$1"; shift; }
            ;;
        --porta|-p) porta="${2:?--porta exige um número}"; shift 2 ;;
        -h|--help)  uso; exit 0 ;;
        *) echo "agent.sh: argumento desconhecido: $1" >&2; uso >&2; exit 2 ;;
    esac
done

if ! command -v MicroXRCEAgent >/dev/null 2>&1; then
    echo "ERRO: MicroXRCEAgent não encontrado." >&2
    echo "      Veja docs/SETUP.md seção 5. O ./doctor.sh também confere isso." >&2
    exit 1
fi

if [[ "$modo" == "serial" ]]; then
    if [[ ! -e "$dispositivo" ]]; then
        echo "ERRO: '$dispositivo' não existe." >&2
        echo >&2
        echo "      Portas seriais vistas agora:" >&2
        ls /dev/ttyTHS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sed 's/^/          /' >&2 \
            || echo "          (nenhuma)" >&2
        echo >&2
        echo "      Compare com e sem o cabo do Pixhawk para saber qual é." >&2
        exit 1
    fi

    if [[ ! -r "$dispositivo" || ! -w "$dispositivo" ]]; then
        echo "ERRO: sem permissão de leitura/escrita em '$dispositivo'." >&2
        echo "      Ponha o usuário no grupo dialout e reentre na sessão:" >&2
        echo "          sudo usermod -aG dialout $USER" >&2
        exit 1
    fi

    # O ModemManager abre toda serial nova para ver se é um modem, e enquanto
    # faz isso o agente não consegue falar com o Pixhawk. O sintoma é o agente
    # subir normalmente e nenhum tópico /fmu/out/* aparecer.
    if systemctl is-active --quiet ModemManager 2>/dev/null; then
        echo "AVISO: o ModemManager está ativo e pode segurar '$dispositivo'." >&2
        echo "       Se nenhum tópico /fmu/out/* aparecer:" >&2
        echo "           sudo systemctl stop ModemManager" >&2
        echo >&2
    fi

    echo "Micro XRCE-DDS Agent — VOO (serial $dispositivo, $baud baud)"
    exec MicroXRCEAgent serial --dev "$dispositivo" -b "$baud"
fi

echo "Micro XRCE-DDS Agent — simulação (UDP porta $porta)"
exec MicroXRCEAgent udp4 -p "$porta"
