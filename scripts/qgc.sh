#!/usr/bin/env bash
# =============================================================================
# qgc.sh — abre o QGroundControl, em qualquer máquina que clonar o repositório.
# =============================================================================
#
#   ./scripts/qgc.sh              procura e abre
#   ./scripts/qgc.sh --onde       só diz onde achou
#   ./scripts/qgc.sh --baixar     busca o AppImage se não houver nenhum
#
# POR QUE PROCURAR, E NÃO FIXAR UM CAMINHO
#
# O QGC é um AppImage solto, e cada máquina do time o guardou num lugar
# diferente -- ~/Downloads, ~/Downloads/apps, ~/Apps, /opt. Um caminho fixo no
# script funcionaria para quem o escreveu e para mais ninguém, e o AppImage é
# grande demais (180 MB) para entrar no repositório.
#
# Então o script procura, na ordem do mais explícito para o mais provável, e
# quem quiser fixar tem dois jeitos: a variável EVTOL_QGC, ou a chave
# `qgc.path` no perfil da máquina em env/<perfil>.yaml. O perfil é o manifesto
# de onde ESTA máquina guarda as coisas -- é o lugar certo.
# =============================================================================
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws_root="$(cd "$script_dir/.." && pwd)"

DESTINO_PADRAO="$HOME/.local/share/evtol/QGroundControl.AppImage"
URL="https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl-x86_64.AppImage"

so_dizer=0
baixar=0

uso() { sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' | grep -v '^=\+$'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --onde)    so_dizer=1; shift ;;
        --baixar)  baixar=1; shift ;;
        -h|--help) uso; exit 0 ;;
        *) echo "qgc.sh: argumento desconhecido: $1" >&2; uso >&2; exit 2 ;;
    esac
done

# ── A busca ──────────────────────────────────────────────────────────────────
procurar() {
    local c

    # 1. A variável de ambiente vence tudo.
    if [[ -n "${EVTOL_QGC:-}" && -f "$EVTOL_QGC" ]]; then
        echo "$EVTOL_QGC"; return 0
    fi

    # 2. O perfil desta máquina, se declarar onde está.
    #
    # `|| true`: a chave é OPCIONAL, e o doctor sai com erro quando o campo não
    # existe. Sem isso o `set -e` mataria o script em toda máquina que não a
    # tivesse declarado -- ou seja, em todas, hoje.
    c="$(python3 "$ws_root/env/doctor.py" --get qgc.path 2>/dev/null || true)"
    if [[ -n "$c" ]]; then
        c="${c/#\~/$HOME}"
        if [[ -f "$c" ]]; then
            echo "$c"; return 0
        fi
        echo "qgc.sh: o perfil aponta 'qgc.path: $c', que não existe." >&2
    fi

    # 3. Instalado de verdade, no PATH.
    if command -v QGroundControl >/dev/null 2>&1; then
        command -v QGroundControl; return 0
    fi

    # 4. Onde AppImage costuma parar. O primeiro que casar vence.
    local dir padrao
    for dir in "$DESTINO_PADRAO" \
               "$HOME/Apps" "$HOME/apps" \
               "$HOME/Downloads/apps" "$HOME/Downloads" \
               "$HOME/Descargas" "$HOME/Downloads/AppImages" \
               "$HOME/.local/share/evtol" "$HOME/.local/bin" \
               /opt/qgc /opt/QGroundControl /opt; do
        [[ -f "$dir" ]] && { echo "$dir"; return 0; }
        [[ -d "$dir" ]] || continue
        # -iname já ignora maiúsculas, então um padrão só cobre .AppImage e
        # .appimage. -maxdepth 1 porque o /opt de uma máquina de trabalho é
        # grande, e varrê-lo demora mais do que abrir o programa.
        padrao="$(find "$dir" -maxdepth 1 -iname '*QGroundControl*.appimage' 2>/dev/null | sort | head -1)"
        [[ -n "$padrao" ]] && { echo "$padrao"; return 0; }
    done

    return 1
}

nao_achei() {
    cat >&2 <<MSG
qgc.sh: não achei o QGroundControl nesta máquina.

  Procurei, nesta ordem:
    \$EVTOL_QGC
    a chave 'qgc.path' do perfil (env/<perfil>.yaml)
    QGroundControl no PATH
    *QGroundControl*.AppImage em ~/Apps, ~/Downloads/apps, ~/Downloads,
      ~/.local/share/evtol, /opt/qgc, /opt

  Se já tem o AppImage em outro lugar, aponte para ele -- uma vez só.
  No env/\$(./doctor.sh --current --curto 2>/dev/null || echo '<perfil>').yaml,
  acrescente:

      qgc:
        path: /caminho/para/QGroundControl.AppImage

  Ou, só para esta sessão:

      export EVTOL_QGC=/caminho/para/QGroundControl.AppImage

  Ou deixe o script buscar:

      ./scripts/qgc.sh --baixar
MSG
}

fazer_download() {
    mkdir -p "$(dirname "$DESTINO_PADRAO")"
    echo "Baixando o QGroundControl (~180 MB) para:"
    echo "    $DESTINO_PADRAO"
    echo
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --progress-bar -o "$DESTINO_PADRAO.parcial" "$URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$DESTINO_PADRAO.parcial" "$URL"
    else
        echo "ERRO: nem curl nem wget nesta máquina." >&2
        echo "      Baixe à mão de $URL" >&2
        exit 1
    fi
    # Só vira o arquivo final quando o download termina inteiro. Um AppImage
    # truncado é executável e falha com uma mensagem que não diz o que houve.
    mv "$DESTINO_PADRAO.parcial" "$DESTINO_PADRAO"
    chmod +x "$DESTINO_PADRAO"
    echo "Pronto."
}

qgc="$(procurar || true)"

if [[ -z "$qgc" ]]; then
    if (( baixar )); then
        fazer_download
        qgc="$DESTINO_PADRAO"
    else
        nao_achei
        exit 1
    fi
fi

if (( so_dizer )); then
    echo "$qgc"
    exit 0
fi

[[ -x "$qgc" ]] || chmod +x "$qgc" 2>/dev/null || true

# O ModemManager abre toda serial nova para ver se é um modem, e nesse tempo o
# QGC não conecta no Pixhawk por USB. O sintoma é o veículo aparecer e sumir,
# ou nunca aparecer -- sem mensagem de erro nenhuma.
if systemctl is-active --quiet ModemManager 2>/dev/null; then
    echo "AVISO: o ModemManager está ativo." >&2
    echo "       Se o QGC não achar o veículo pela USB:" >&2
    echo "           sudo systemctl stop ModemManager" >&2
    echo >&2
fi

echo "QGroundControl: $qgc"

# AppImage precisa de FUSE. Onde não houver (contêiner, Jetson enxuta, WSL), o
# próprio AppImage sabe se extrair e rodar -- mas só se pedirem. Sem isto a
# falha é um "dlopen(): error loading libfuse.so.2" que não sugere saída.
if [[ "$qgc" == *.[Aa]pp[Ii]mage ]] && ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    echo "  (sem libfuse2: extraindo e rodando)"
    exec "$qgc" --appimage-extract-and-run "$@"
fi

exec "$qgc" "$@"
