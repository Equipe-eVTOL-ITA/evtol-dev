#!/usr/bin/env bash
# =============================================================================
# Commita e pusha UM repositorio do workspace.
#
#     scripts/git_push.sh <repo> <mensagem> <com CI|sem CI>
#
# Chamado pela task "git: commitar e pushar" do VS Code, mas serve no terminal.
#
# O QUE "SEM CI" FAZ: acrescenta `[skip ci]` a mensagem. O GitHub Actions le
# isso na mensagem do commit do topo e nao dispara os workflows. Nao desliga
# nada no repositorio -- vale so para este push, e o proximo commit sem a marca
# volta a rodar o CI normalmente.
#
# QUANDO USAR "sem CI": quando voce vai empurrar varios commits seguidos e so
# o ultimo precisa ser verificado, ou quando esta sem tempo de esperar o build.
# O custo e real: um push sem CI e um push cuja unica verificacao foi a sua.
# Se o codigo vai para a `main` e de la para a Jetson, alguem tem de compilar.
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

repo="${1:-}"
mensagem="${2:-}"
modo_ci="${3:-com CI}"

if [[ -z "$repo" || -z "$mensagem" ]]; then
  echo "uso: scripts/git_push.sh <repo> <mensagem> [com CI|sem CI]" >&2
  exit 2
fi

# O evtol-dev e a raiz do workspace; todo o resto mora em src/.
if [[ "$repo" == "evtol-dev" ]]; then
  dir="$RAIZ"
else
  dir="$RAIZ/src/$repo"
fi

if [[ ! -d "$dir/.git" ]]; then
  echo "ERRO: '$repo' nao e um repositorio git ($dir)." >&2
  exit 1
fi

cd "$dir"
echo "=== $repo  ($dir)"

ramo="$(git rev-parse --abbrev-ref HEAD)"

# Detached HEAD: o `vcs import` deixa todo repo pinado assim, e commit em
# detached nao pertence a branch nenhum -- some do radar no proximo checkout.
if [[ "$ramo" == "HEAD" ]]; then
  cat >&2 <<'FIM'
ERRO: este repositorio esta em detached HEAD.

O `vcs import` deixa cada repo na TAG pinada, que nao e branch. Commitar aqui
produz um commit que nao pertence a lugar nenhum. Saia primeiro:

    git checkout -b <tipo>/<descricao-curta>      # se ja mexeu em algo
    git checkout main && git pull                 # se ainda nao mexeu

Ver docs/GIT.md, secao 3.
FIM
  exit 1
fi

# Nunca commitar na main -- a regra da equipe, e a que mais custa quando quebra:
# duas maquinas com "main" diferentes e ninguem sabe qual versao e a atual.
if [[ "$ramo" == "main" || "$ramo" == "master" ]]; then
  cat >&2 <<FIM
ERRO: voce esta na '$ramo', e a equipe nao commita direto na main.

Leve o trabalho para um branch antes -- nada se perde, o que ja esta no
diretorio de trabalho vem junto:

    cd $dir
    git checkout -b <tipo>/<descricao-curta>

Prefixos: feat/ fix/ docs/ chore/ refactor/ ci/ style/
Ver docs/GIT.md, secao 4.
FIM
  exit 1
fi

if [[ -z "$(git status --porcelain)" ]]; then
  echo "Nada a commitar; a arvore esta limpa."
  # Mesmo sem novidade local pode haver commit ainda nao publicado.
  if [[ -n "$(git log --branches --not --remotes -n1 --format=%H 2>/dev/null)" ]]; then
    echo "Ha commit nao publicado. Empurrando..."
    git push -u origin "$ramo"
  fi
  exit 0
fi

echo
echo "--- o que vai entrar no commit ---"
git status --short
echo

# `[skip ci]` na mensagem e o que o GitHub Actions le para nao disparar.
final="$mensagem"
if [[ "$modo_ci" == sem* ]]; then
  final="$mensagem

[skip ci]"
  echo ">>> SEM CI: o commit leva [skip ci]; nenhum workflow vai rodar."
  echo ">>> A unica verificacao deste push e a que voce fez na sua maquina."
else
  echo ">>> COM CI: os workflows do repositorio vao rodar neste push."
fi
echo

git add -A
git commit -m "$final"
git push -u origin "$ramo"

echo
echo "=== pronto: $repo -> origin/$ramo"

# O manifesto pina TAG, nao branch: mergear na main nao muda nada para as
# outras maquinas ate a tag nova subir no evtol.repos. E o passo que todo mundo
# esquece, e o motivo de a Jetson as vezes voar codigo antigo.
if [[ "$repo" != "evtol-dev" ]]; then
  echo
  echo "Falta o PR. E, depois do merge, a TAG e o pin no evtol.repos --"
  echo "sem isso o seu trabalho nao chega a Jetson. Ver docs/GIT.md, secao 9."
fi
