#!/usr/bin/env bash
# =============================================================================
# setup.sh — bootstrap do workspace eVTOL ITA.
# =============================================================================
#
#   mkdir -p ~/evtol/dev && cd ~/evtol/dev
#   git clone https://github.com/Equipe-eVTOL-ITA/evtol-dev.git src/evtol-dev
#   ./src/evtol-dev/setup.sh --profile desktop-humble
#
# Faz, nesta ordem:
#   1. verifica o ambiente contra o perfil (doctor.sh) — PORTÃO
#   2. importa todos os repos nas versões pinadas (evtol.repos)
#   3. instala dependências de sistema (rosdep)
#   4. compila
#
# O passo 1 vem primeiro de propósito. Compilar num ambiente errado não gera
# um erro que aponta para a causa: gera comportamento estranho horas depois.
# É mais barato falhar aqui, com a linha de correção na tela.
#
# Pré-requisitos que NÃO são instalados por este script (vivem fora do
# workspace colcon): PX4-Autopilot, Micro-XRCE-DDS-Agent e, opcionalmente,
# PX4-gazebo-models. Veja SETUP.md seções 4-5. As versões deles são pinadas
# em env/<perfil>.yaml e conferidas pelo doctor.
# =============================================================================

set -euo pipefail

profile=""
skip_doctor=0

usage() {
    cat <<'EOF'
Uso: setup.sh [--profile <nome>] [--skip-doctor]

  --profile <nome>   perfil de ambiente (ex.: desktop-humble).
                     Se omitido, usa o conteúdo de .evtol-profile.
                     Liste os disponíveis com: ./doctor.sh --list
  --skip-doctor      pula a verificação de ambiente. NÃO use isso para
                     "resolver" uma falha do doctor — a falha é real.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile|-p) profile="${2:-}"; shift 2 ;;
        --skip-doctor) skip_doctor=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERRO: argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# O repo evtol-dev pode estar em src/evtol-dev/ (layout atual) ou ser ele
# próprio a raiz do workspace. Detecta os dois para que a reorganização da
# estrutura não quebre este script.
if [[ -d "$script_dir/src" && -f "$script_dir/evtol.repos" ]]; then
    ws_root="$script_dir"                       # evtol-dev É a raiz
    meta_dir="$script_dir"
else
    ws_root="$(cd "$script_dir/../.." && pwd)"  # evtol-dev está em src/
    meta_dir="$script_dir"
fi
cd "$ws_root"

echo "==> Raiz do workspace: $ws_root"

manifest="$meta_dir/evtol.repos"
if [[ ! -f "$manifest" ]]; then
    echo "ERRO: manifesto não encontrado em $manifest" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Perfil
# ---------------------------------------------------------------------------
if [[ -z "$profile" && -f "$ws_root/.evtol-profile" ]]; then
    profile="$(tr -d '[:space:]' < "$ws_root/.evtol-profile")"
fi

if [[ -z "$profile" ]]; then
    echo "ERRO: nenhum perfil selecionado." >&2
    echo >&2
    echo "  O perfil determina a distro do ROS, a versão do Gazebo, a variante" >&2
    echo "  do bridge e os pins de apt/pip desta máquina. Ele não tem padrão" >&2
    echo "  porque adivinhar errado é justamente o bug que queremos eliminar." >&2
    echo >&2
    echo "  Veja os disponíveis:  $meta_dir/doctor.sh --list" >&2
    echo "  Depois:               ./setup.sh --profile <nome>" >&2
    exit 1
fi

profile_file="$meta_dir/env/$profile.yaml"
if [[ ! -f "$profile_file" ]]; then
    echo "ERRO: perfil '$profile' não existe ($profile_file)." >&2
    echo "      Disponíveis: $("$meta_dir/doctor.sh" --list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')" >&2
    exit 1
fi

echo "==> Perfil: $profile"

# A distro do ROS vem do perfil, nunca de um valor fixo aqui. É o que permite
# que a mesma ferramenta sirva a Jetson (humble) e a Raspberry (jazzy).
ros_distro="$(python3 -c "
import sys, yaml
spec = yaml.safe_load(open('$profile_file')) or {}
print((spec.get('ros') or {}).get('distro', ''))
")"

if [[ -z "$ros_distro" ]]; then
    echo "ERRO: o perfil '$profile' não declara ros.distro." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Portão: ambiente
# ---------------------------------------------------------------------------
if [[ -z "${ROS_DISTRO:-}" ]]; then
    if [[ -f "/opt/ros/$ros_distro/setup.bash" ]]; then
        echo "==> Carregando /opt/ros/$ros_distro/setup.bash"
        # shellcheck disable=SC1090
        source "/opt/ros/$ros_distro/setup.bash"
    else
        echo "ERRO: ROS 2 $ros_distro não encontrado em /opt/ros/$ros_distro." >&2
        echo "      O perfil '$profile' exige essa distro. Veja SETUP.md seção 2." >&2
        exit 1
    fi
fi

if [[ "$skip_doctor" -eq 1 ]]; then
    echo "==> AVISO: verificação de ambiente PULADA (--skip-doctor)."
    echo "    Se algo se comportar de forma estranha adiante, rode:"
    echo "        $meta_dir/doctor.sh --profile $profile"
else
    echo "==> Verificando o ambiente contra o perfil"
    if ! "$meta_dir/doctor.sh" --profile "$profile"; then
        echo >&2
        echo "ERRO: o ambiente não confere com o perfil '$profile'." >&2
        echo "      Corrija os itens acima e rode o setup.sh de novo." >&2
        echo "      Cada um deles já quebrou o time antes; nenhum é cosmético." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. Código
# ---------------------------------------------------------------------------
for tool in vcs colcon rosdep; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERRO: '$tool' não está no PATH. Veja SETUP.md seções 1-2." >&2
        exit 1
    }
done

echo "==> Importando repositórios (vcs import src < $manifest)"
mkdir -p src
vcs import src < "$manifest"

# ---------------------------------------------------------------------------
# 3. Dependências de sistema
# ---------------------------------------------------------------------------
echo "==> Instalando dependências (rosdep)"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    echo "    rosdep ainda não foi inicializado nesta máquina. Rode uma vez:"
    echo "        sudo rosdep init && rosdep update"
    echo "    Seguindo sem ele; se faltar dependência, o build abaixo vai acusar."
else
    rosdep update >/dev/null 2>&1 || echo "    AVISO: 'rosdep update' falhou; usando o cache local."
    rosdep install --from-paths src --ignore-src -y --rosdistro "$ros_distro" ||
        echo "    AVISO: o rosdep reportou erros acima — revise antes de voar."
fi

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
# --executor sequential evita picos de RAM (veja SETUP.md, seção de swap).
echo "==> Compilando (colcon build --symlink-install --executor sequential)"
colcon build --symlink-install --executor sequential

# Registra o perfil só depois que tudo deu certo, para que .evtol-profile não
# aponte para um perfil que nunca chegou a funcionar nesta máquina.
echo "$profile" > "$ws_root/.evtol-profile"

cat <<EOF

Pronto. Perfil '$profile' registrado em $ws_root/.evtol-profile
(as próximas execuções de setup.sh e doctor.sh já o usam por padrão).

Em cada shell novo:
    source /opt/ros/$ros_distro/setup.bash
    source $ws_root/install/setup.bash
EOF
