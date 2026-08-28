#!/usr/bin/env bash
# =============================================================================
# Congela o workspace: gera o voo.repos com a revisao EXATA de cada repositorio.
#
#     scripts/congelar.sh [arquivo]        # padrao: voo.repos
#
# QUANDO RODAR: antes de competir ou de um voo que importa, na maquina onde
# voce acabou de compilar e testar. O que ele grava e o que esta ali, nao o que
# alguem escreveu num arquivo semanas atras.
#
# POR QUE ELE EXISTE. O evtol.repos acompanha a `main` dos repositorios da
# equipe -- e essa e a escolha certa para o dia a dia: sem detached HEAD, sem
# um segundo pull request so para subir um pin. Mas "a main de hoje" nao e uma
# resposta aceitavel para "o que exatamente voou naquele dia". Este script
# produz essa resposta, no unico momento em que ela vale alguma coisa.
#
# COMO USAR o arquivo gerado, na Jetson ou na Raspberry:
#
#     ./setup.sh --manifesto voo.repos
#
# O voo.repos NAO e versionado por padrao. Se um voo merece ficar registrado,
# commite-o com nome proprio -- `cbr2026-final.repos` -- e a pergunta "o que
# voou na final" passa a ter resposta para sempre.
# =============================================================================
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

saida="${1:-voo.repos}"

if [[ ! -d src ]]; then
    echo "ERRO: nao existe src/ em $raiz. Rode o ./setup.sh antes." >&2
    exit 1
fi

# Trabalho nao commitado nao entra num hash. Congelar por cima disso produz um
# manifesto que descreve outro codigo que nao o que voce testou -- e o erro so
# aparece quando alguem tentar reproduzir o voo.
sujos=()
for d in src/*/; do
    [[ -d "$d/.git" ]] || continue
    [[ -n "$(git -C "$d" status --porcelain)" ]] && sujos+=("$(basename "$d")")
done

if (( ${#sujos[@]} )); then
    echo "AVISO: estes repositorios tem trabalho nao commitado:" >&2
    printf '  %s\n' "${sujos[@]}" >&2
    echo >&2
    echo "O congelamento grava COMMITS. O que nao esta commitado nao vai para o" >&2
    echo "$saida, e a maquina que importar este manifesto nao tera essas" >&2
    echo "mudancas. Commite e publique antes (task 'git: publicar')." >&2
    echo >&2
    read -r -p "Congelar assim mesmo? [s/N] " r
    [[ "$r" =~ ^[sS] ]] || { echo "Cancelado."; exit 1; }
fi

# --exact-with-tags: usa o nome da tag onde existe uma que identifique o commit
# (os repositorios de terceiros seguem legiveis: v1.15.4, 4.9.1) e cai para o
# hash de 40 caracteres no resto. Os dois sao imutaveis; um deles se le.
vcs export --exact-with-tags src > "$saida"

echo "=== $saida"
python3 - "$saida" <<'PY'
import sys, yaml
repos = yaml.safe_load(open(sys.argv[1]))["repositories"]
for nome, r in sorted(repos.items()):
    print(f"  {nome:<22} {r['version']}")
print(f"\n{len(repos)} repositorios congelados.")
print("Para reproduzir este workspace noutra maquina:")
print(f"    ./setup.sh --manifesto {sys.argv[1]}")
PY
