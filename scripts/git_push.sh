#!/usr/bin/env bash
# =============================================================================
# Publica UM repositorio do workspace: do arquivo editado ate o PR mergeado.
#
#     scripts/git_push.sh <repo> <mensagem> [com CI|sem CI]
#
# Chamado pela task "git: publicar" do VS Code, mas serve no terminal.
#
# O QUE ELE FAZ, na ordem:
#
#     1. cria o branch, se voce estiver na main (ninguem commita na main)
#     2. commita o que esta no diretorio de trabalho
#     3. empurra
#     4. abre o pull request (`gh pr create --fill`)
#     5. liga o auto-merge: o PR se mergeia sozinho quando o CI ficar verde
#
# Voce nao precisa esperar, nem voltar depois para clicar em nada. E nao ha
# mais tag nem repin: o evtol.repos acompanha a `main` dos repositorios da
# equipe, entao o merge ja chega em todo mundo -- basta um `git pull` (ou a
# task "git: atualizar tudo").
#
# O QUE "SEM CI" FAZ: acrescenta `[skip ci]` a mensagem, e o GitHub Actions nao
# dispara os workflows. Como o auto-merge espera justamente o CI ficar verde,
# nesse modo ele NAO e ligado -- o PR fica aberto para voce decidir. Use quando
# for empurrar varios commits seguidos e so o ultimo precisar ser verificado.
# O custo e real: um push sem CI e um push cuja unica verificacao foi a sua.
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

# ---------------------------------------------------------------------------
# 1. O branch
# ---------------------------------------------------------------------------
ramo="$(git rev-parse --abbrev-ref HEAD)"

# Detached HEAD deixou de ser o caso comum -- o manifesto pina `main`, e o
# `vcs import` deixa cada repositorio em branch. Mas quem faz `git checkout` de
# uma tag a mao ainda cai aqui, e commitar em detached produz um commit que nao
# pertence a lugar nenhum.
if [[ "$ramo" == "HEAD" ]]; then
  echo "Este repositorio esta em detached HEAD (alguem deu checkout numa tag?)." >&2
  echo "Levando o trabalho para um branch antes de seguir." >&2
  ramo=""
fi

# Estar na main nao e mais erro fatal: o script cria o branch e segue. Antes
# ele abortava aqui e mandava a pessoa rodar `git checkout -b` sozinha -- um
# passo a mais para aprender, num ponto em que ela ja tinha o trabalho pronto.
if [[ -z "$ramo" || "$ramo" == "main" || "$ramo" == "master" ]]; then
  # O nome sai da propria mensagem: "fix: pouso ultrapassa" -> fix/pouso-ultrapassa.
  novo="$(python3 - "$mensagem" <<'PY'
import re, sys, unicodedata
msg = sys.argv[1].strip()
m = re.match(r"^(feat|fix|docs|chore|refactor|ci|style|test)!?:\s*(.+)$", msg, re.I)
tipo, resto = (m.group(1).lower(), m.group(2)) if m else ("feat", msg)
resto = unicodedata.normalize("NFKD", resto).encode("ascii", "ignore").decode()
slug = re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", resto.lower())).strip("-")
print(f"{tipo}/{'-'.join(slug.split('-')[:6]) or 'trabalho'}")
PY
)"
  echo ">>> Voce estava na '${ramo:-detached}'. Criando o branch: $novo"
  git checkout -b "$novo"
  ramo="$novo"
fi

# ---------------------------------------------------------------------------
# 2. O commit
# ---------------------------------------------------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo
  echo "--- o que vai entrar no commit ---"
  git status --short
  echo

  final="$mensagem"
  if [[ "$modo_ci" == sem* ]]; then
    final="$mensagem

[skip ci]"
    echo ">>> SEM CI: o commit leva [skip ci]; nenhum workflow vai rodar."
    echo ">>> A unica verificacao deste push e a que voce fez na sua maquina."
  fi
  echo

  git add -A
  git commit -m "$final"
else
  echo "Nada a commitar; a arvore esta limpa."
  if [[ -z "$(git log --branches --not --remotes -n1 --format=%H 2>/dev/null)" ]]; then
    echo "E nada por publicar. Saindo."
    exit 0
  fi
  echo "Ha commit ainda nao publicado; seguindo."
fi

# ---------------------------------------------------------------------------
# 3. O push
# ---------------------------------------------------------------------------
git push -u origin "$ramo"
echo "=== publicado: $repo -> origin/$ramo"

# ---------------------------------------------------------------------------
# 4. e 5. O pull request, e o auto-merge
# ---------------------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo
  echo "O 'gh' nao esta instalado, entao o pull request fica por sua conta:"
  echo "    sudo apt install gh && gh auth login"
  echo "Ou abra o PR pelo browser. Ver docs/GIT.md."
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "O 'gh' nao esta autenticado. Uma vez por maquina:"
  echo "    gh auth login        # GitHub.com -> HTTPS -> autenticar pelo browser"
  exit 0
fi

# Um branch pode ja ter PR (segundo push do mesmo trabalho). Nesse caso nao se
# cria outro -- so se garante que o auto-merge esta ligado.
url="$(gh pr view --json url --jq .url 2>/dev/null || true)"
if [[ -z "$url" ]]; then
  echo
  echo "--- abrindo o pull request ---"
  gh pr create --fill
  url="$(gh pr view --json url --jq .url 2>/dev/null || true)"
else
  echo
  echo "--- este branch ja tem pull request ---"
fi

if [[ "$modo_ci" == sem* ]]; then
  echo
  echo ">>> Auto-merge NAO ligado: com [skip ci] o CI nao roda, e o auto-merge"
  echo ">>> espera justamente ele ficar verde. O PR fica aberto para voce."
  echo "$url"
  exit 0
fi

# --auto: o GitHub segura o merge ate o CI passar, e mergeia sozinho. Se o
# repositorio ainda nao tiver o auto-merge habilitado nas Settings, o gh
# recusa -- e ai o merge fica manual, que e o comportamento de antes.
if gh pr merge --auto --squash 2>/dev/null; then
  echo
  echo "=== auto-merge ligado. Este PR se mergeia sozinho quando o CI ficar verde."
  echo "    Voce nao precisa voltar aqui."
else
  echo
  echo "AVISO: nao foi possivel ligar o auto-merge neste repositorio."
  echo "       (Settings -> General -> 'Allow auto-merge'.)"
  echo "       O PR esta aberto; o merge fica manual."
fi

echo "$url"
