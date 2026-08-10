# Migrando um workspace existente para a raiz versionada

Só é preciso fazer isto **uma vez por máquina**, e só em máquinas que já tinham
o workspace no layout antigo (`evtol-dev` clonado dentro de `src/`). Quem for
instalar do zero deve seguir [SETUP.md](SETUP.md) e ignorar este documento.

## O que muda

| Antes | Depois |
|---|---|
| `~/evtol/dev/` não era repositório git | `~/evtol/dev/` **é** o repositório `evtol-dev` |
| `~/evtol/dev/src/evtol-dev/` | deixa de existir |
| `.vscode/` e `scripts/` copiados na mão para a raiz | versionados na raiz, sem cópia |
| `ARCHITECTURE.md`, `SETUP.md` na raiz do repo | em `docs/` |

`src/`, `build/`, `install/` e `log/` passam a ser ignorados pelo git da raiz.
**Nada em `src/` é apagado pela migração** — os repositórios de lá continuam
sendo os mesmos, com o mesmo git e os mesmos branches.

## Antes de começar

Confira que não há trabalho não commitado que você possa perder:

```bash
cd ~/evtol/dev
git -C src/evtol-dev status --short          # tem que estar limpo
for d in src/*/; do
    printf '%-24s %s\n' "$d" "$(git -C "$d" status --porcelain 2>/dev/null | wc -l) alterações"
done
```

Commite e faça push do que estiver pendente antes de seguir.

## Migração

```bash
cd ~/evtol/dev

# 1. Guarde os arquivos soltos da raiz. Eles não eram versionados por ninguém,
#    e alguns vão ser substituídos pelas versões oficiais do repositório.
mkdir -p ~/evtol/_backup_pre_migracao
mv .vscode scripts README.md .gitignore ~/evtol/_backup_pre_migracao/ 2>/dev/null

# 2. Promova o repositório evtol-dev de src/ para a raiz.
mv src/evtol-dev/.git .git
rm -rf src/evtol-dev

# 3. Traga o layout novo (doctor.sh, env/, docs/, .vscode/, scripts/, ...).
git fetch origin
git checkout main
git reset --hard origin/main

# 4. Registre o perfil desta máquina.
echo desktop-humble > .evtol-profile     # ou jetson-humble / rpi-jazzy

# 5. Confira.
./doctor.sh
```

## Depois

```bash
git status --short
```

Deve sair **vazio**. Se `src/`, `build/`, `install/` ou `log/` aparecerem, o
`.gitignore` não foi aplicado — confirme que o passo 3 completou.

Para reconstruir sem reimportar nada:

```bash
source scripts/ros_env.sh
colcon build --symlink-install --executor sequential
```

## Sobre os arquivos que você guardou no backup

- **`scripts/build.sh`, `simulate.sh`, `agent.sh` da raiz** — eram cópias
  desatualizadas das versões que vivem em `src/sae2026/scripts/`, e a cópia de
  `build.sh` estava **quebrada** (resolvia `WORKSPACE_DIR` para fora do
  workspace). Descarte: use `src/sae2026/scripts/`. Pela regra
  *"cada competição tem os seus scripts"*, eles nunca deveriam ter sido
  copiados para a raiz.
- **`.vscode/tasks.json`** — a versão oficial já vem versionada na raiz. Se
  você tinha tasks próprias, compare com o backup e traga o que fizer sentido
  num PR.
- **`README.md` e `.gitignore` da raiz** — substituídos pelas versões do
  repositório.

Confira também se sobrou algo solto e não versionado dentro de `src/`:

```bash
ls src/*.md 2>/dev/null
```

No workspace de referência havia dois (`walkthrough.md` e
`gazebo_models_setup.md`); ambos passaram a viver em `docs/`. Se houver outros,
eles não estão em repositório nenhum — decida onde devem morar antes de perdê-los.

> Um caso concreto: o pacote `mission_teste` foi removido do `sae2026` num
> branch local que nunca foi enviado, e a cópia de trabalho ficou solta em
> `src/mission_teste`. Ele não existe em nenhum repositório. Se estiver na sua
> máquina, recupere-o (`git show v0.1.0:mission_teste/` no `sae2026`) ou
> confirme que pode ser descartado.
