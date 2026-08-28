#!/usr/bin/env bash
# =============================================================================
# Aplica a politica de branch da organizacao a um ou mais repositorios.
#
#     scripts/proteger.sh --listar                  # como esta hoje
#     scripts/proteger.sh <repo>...                 # o que MUDARIA (nao muda)
#     scripts/proteger.sh --aplicar <repo>...       # muda de verdade
#     scripts/proteger.sh --aplicar --todos
#
# A POLITICA, IGUAL EM TODO REPOSITORIO:
#
#     pull request obrigatorio ................ sim (zero aprovacoes exigidas)
#     checks obrigatorios ..................... um so: o build
#     branch atualizado com a main (strict) ... NAO
#     force push / apagar a main .............. bloqueados
#     auto-merge .............................. ligado
#     apagar o branch depois do merge ......... ligado
#
# POR QUE ASSIM. A politica anterior variava por repositorio -- tres deles
# exigiam uma aprovacao humana e branch atualizado com a main -- e a tabela de
# "o que cada repositorio exige" era uma pagina inteira de documentacao que
# ninguem decorava. As duas travas que sairam sao as unicas que custam ESPERA:
#
#   - a aprovacao depende de outra pessoa estar disponivel, e era descartada a
#     cada push novo;
#   - o `strict` obriga a atualizar o branch a cada merge alheio, e a re-rodar
#     o CI inteiro -- com vinte membros, isso e uma fila.
#
# O que ficou custa zero espera: e automatico e instantaneo. Revisao continua
# sendo pedida e valorizada; deixou de ser portao.
#
# E idempotente: rodar duas vezes nao muda nada na segunda.
# =============================================================================
set -euo pipefail

ORG="Equipe-eVTOL-ITA"

# O evtol-dev nao tem codigo compilavel: o check dele tem outro nome.
check_de() {
  case "$1" in
    evtol-dev) echo "manifesto, perfis e scripts" ;;
    *)         echo "build (humble)" ;;
  esac
}

TODOS=(evtol-dev camera_publisher cbr2026 custom_msgs cv_nodes drone_lib
       ensaio_em_voo fsm maze_geometry ozzy_bridge sae2026 sim2d stdbt
       stdstates telemetry_handler vision_geometry)

aplicar=0
listar=0
repos=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aplicar) aplicar=1; shift ;;
    --listar)  listar=1; shift ;;
    --todos)   repos+=("${TODOS[@]}"); shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    -*) echo "ERRO: argumento desconhecido: $1" >&2; exit 2 ;;
    *) repos+=("$1"); shift ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "ERRO: o 'gh' nao esta instalado." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERRO: rode 'gh auth login' antes." >&2; exit 1; }

# ---------------------------------------------------------------------------
# --listar: o estado de hoje, sem mudar nada
# ---------------------------------------------------------------------------
if (( listar )); then
  (( ${#repos[@]} )) || repos=("${TODOS[@]}")
  for r in "${repos[@]}"; do
    printf '%-22s ' "$r"
    # O `gh api` sai diferente de zero em repositorio sem protecao (404) e
    # ainda assim escreve o JSON do erro na saida. Com `pipefail`, um `||`
    # depois do pipe dispararia ALEM da linha que o python ja imprimiu -- duas
    # linhas para o mesmo repositorio. Quem decide e o python, olhando o corpo.
    gh api "repos/$ORG/$r/branches/main/protection" 2>/dev/null | python3 -c '
import json, sys
t = sys.stdin.read().strip()
if not t:
    print("SEM PROTECAO"); raise SystemExit
d = json.loads(t)
if "message" in d and "required_status_checks" not in d:
    print("SEM PROTECAO"); raise SystemExit
rc = d.get("required_status_checks") or {}
pr = d.get("required_pull_request_reviews")
print("checks=%s strict=%s aprovacoes=%s force_push=%s" % (
    rc.get("contexts"), rc.get("strict"),
    (pr or {}).get("required_approving_review_count", "-") if pr else "PR nao exigido",
    (d.get("allow_force_pushes") or {}).get("enabled")))
' || true
  done
  exit 0
fi

(( ${#repos[@]} )) || { echo "ERRO: informe repositorios, ou --todos." >&2; exit 2; }

if (( ! aplicar )); then
  echo "=== SIMULACAO. Nada sera mudado. Repita com --aplicar para valer. ==="
  echo
fi

for r in "${repos[@]}"; do
  check="$(check_de "$r")"
  echo "=== $ORG/$r"

  # ARMADILHA. Exigir um check que nenhum workflow produz trava TODO merge
  # daquele repositorio, para sempre: o GitHub fica esperando um status que
  # nunca vai chegar, e nao ha o que clicar. Hoje maze_geometry, sae2026 e
  # sim2d nao tem workflow nenhum. Neles a protecao entra sem check exigido --
  # o pull request e o bloqueio de force push continuam valendo.
  if gh api "repos/$ORG/$r/actions/workflows" -q '.workflows[].name' 2>/dev/null | grep -q .; then
    tem_ci=1
    echo "    check obrigatorio: '$check'  |  strict: nao  |  aprovacoes: 0"
  else
    tem_ci=0
    echo "    check obrigatorio: NENHUM (este repositorio nao tem workflow)"
    echo "    strict: nao  |  aprovacoes: 0"
    echo "    -> copie templates/workflows/build.yml para ele e rode isto de novo."
  fi
  echo "    auto-merge: ligado  |  apagar branch no merge: ligado"

  if (( ! aplicar )); then echo; continue; fi

  # A protecao de branch. `required_approving_review_count: 0` exige o pull
  # request SEM exigir que alguem aprove -- que e exatamente a politica.
  # `enforce_admins: false` deixa um administrador destravar uma emergencia
  # em dia de competicao sem ter de desligar a protecao inteira.
  python3 - "$ORG/$r" "$check" "$tem_ci" <<'PY' | gh api -X PUT "repos/$ORG/$r/branches/main/protection" --input - >/dev/null
import json, sys
print(json.dumps({
    "required_status_checks": (
        {"strict": False, "contexts": [sys.argv[2]]} if sys.argv[3] == "1" else None),
    "enforce_admins": False,
    "required_pull_request_reviews": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews": False,
        "require_code_owner_reviews": False,
    },
    "restrictions": None,
    "allow_force_pushes": False,
    "allow_deletions": False,
}))
PY

  gh api -X PATCH "repos/$ORG/$r" \
    -F allow_auto_merge=true -F delete_branch_on_merge=true \
    -F allow_squash_merge=true >/dev/null

  echo "    aplicado."
  echo
done

if (( aplicar )); then
  echo "Confira com: scripts/proteger.sh --listar"
fi
