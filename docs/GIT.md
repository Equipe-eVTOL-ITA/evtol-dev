# Como mandar código para o GitHub

**Guia prático para os membros da equipe eVTOL ITA.**

Este documento responde a uma pergunta só: *acabei de mexer num arquivo — o que
eu faço para isso chegar ao GitHub do jeito certo?*

As regras existem por um motivo concreto: a equipe voa com **duas distros ao
mesmo tempo** (Jetson/Humble e Raspberry/Jazzy), o código está espalhado por
**dezesseis repositórios** e o que roda numa competição é o que está **pinado no
manifesto**. Cada regra abaixo evita uma classe de erro que já custou tempo de
voo.

---

## Índice

1. [Antes de tudo — a máquina configurada](#1-antes-de-tudo--a-máquina-configurada)
2. [Onde o seu arquivo mora](#2-onde-o-seu-arquivo-mora)
3. [⚠️ Sair do detached HEAD (leia antes do primeiro commit)](#3-️-sair-do-detached-head)
4. [O branch](#4-o-branch)
5. [O commit](#5-o-commit)
6. [O que nunca vai para o repositório](#6-o-que-nunca-vai-para-o-repositório)
7. [O push e o Pull Request](#7-o-push-e-o-pull-request)
8. [O que cada repositório exige hoje](#8-o-que-cada-repositório-exige-hoje)
9. [Depois do merge — a tag e o pin](#9-depois-do-merge--a-tag-e-o-pin)
10. [Regras extras do evtol-dev](#10-regras-extras-do-evtol-dev)
11. [Quando dá errado](#11-quando-dá-errado)
12. [A cola](#12-a-cola)

---

## 1. Antes de tudo — a máquina configurada

Uma vez por máquina:

```bash
git config --global user.name  "Seu Nome Completo"
git config --global user.email "seu-email-do-github@exemplo.com"
```

Use **o mesmo e-mail cadastrado no GitHub** — senão os commits aparecem sem
rosto e sem vínculo com a sua conta.

Para autenticar (o GitHub não aceita mais senha no `git push`), o caminho curto
é o `gh`:

```bash
sudo apt install gh        # se ainda não tiver
gh auth login              # escolha: GitHub.com → HTTPS → autenticar pelo browser
```

Confira:

```bash
gh auth status
```

---

## 2. Onde o seu arquivo mora

**Não existe "o repositório da equipe".** Existem dezesseis, e o que decide para
onde você commita é **onde o arquivo que você editou está**, não de onde você
rodou o comando.

| Você mexeu em... | O repositório é | O `git` roda em |
|---|---|---|
| Lógica de uma fase da competição | `cbr2026`, `sae2026`, `itajuba2026` | `src/<competição>/` |
| Um estado reutilizável de FSM | `stdstates` | `src/stdstates/` |
| Um nó de visão / detector | `cv_nodes` | `src/cv_nodes/` |
| Uma capacidade do veículo (PX4) | `drone_lib` | `src/drone_lib/` |
| Um tipo de mensagem novo | `custom_msgs` | `src/custom_msgs/` |
| Manifesto, perfis, scripts da raiz, tasks, docs do workspace | `evtol-dev` | `~/evtol/dev/` |

> **`src/` é ignorado pelo git do `evtol-dev`.** Isso é de propósito: cada pasta
> dentro de `src/` tem o seu próprio repositório. Se você rodar `git add -A` na
> raiz esperando levar junto uma mudança em `src/stdstates/`, ela **não vai** —
> e você vai achar que subiu.

Para saber onde está trabalho solto em todo o workspace de uma vez:

```bash
cd ~/evtol/dev
for d in src/*/; do
    printf '%-24s %s alterações\n' "$(basename "$d")" \
      "$(git -C "$d" status --porcelain 2>/dev/null | wc -l)"
done
```

(Ou a task do VS Code **perfil** / o `./doctor.sh`, que avisam sobre trabalho
solto.)

---

## 3. ⚠️ Sair do detached HEAD

**Este é o erro número um de quem chega no workspace. Leia antes de commitar.**

O `evtol.repos` pina **tags**, e tag não é branch. Depois de um `vcs import`,
todo repositório em `src/` fica assim:

```bash
$ git -C src/drone_lib status
HEAD detached at v0.4.0
```

Nesse estado você **compila e roda normalmente**, mas **não deve commitar**: um
commit em detached HEAD não pertence a branch nenhum e some do seu radar assim
que você trocar de tag.

**Sempre que for mexer no código de um repositório, comece por aqui:**

```bash
cd ~/evtol/dev/src/drone_lib
git checkout main                 # sai do detached
git pull                          # traz o que os outros já mergearam
git checkout -b fix/meu-ajuste    # e só então trabalhe
```

Se você **já commitou** em detached HEAD, nada se perdeu — crie um branch ali
mesmo, **antes de sair**:

```bash
git switch -c recupera-meu-trabalho
```

---

## 4. O branch

Regras, todas com o mesmo objetivo — que ninguém precise adivinhar "qual versão
é a atual":

- **Nunca commite direto na `main`.** Nem local. Branch sempre.
- **Um trabalho = um branch = uma pessoa.** Duas pessoas na mesma feature
  trabalham *no mesmo branch*, não em dois paralelos.
- **O nome descreve o trabalho, não a pessoa nem a máquina.**
  `feat/busca-em-h`, `fix/pouso-ultrapassa` — nunca `angelo`, `jetson`, `teste2`.
- **Nada de "branch de deploy".** `jetson`, `bronco` e afins que divergem da
  `main` por semanas são o problema que essas regras vieram resolver. Se duas
  máquinas precisam de comportamentos diferentes, isso é configuração (YAML,
  argumento de launch) — não um fork.
- **Abra o PR em poucos dias, feche em uma ou duas semanas.** O PR é a conversa
  sobre o trabalho, não a comemoração depois dele.

Os prefixos de branch são os mesmos do commit:

| Prefixo | Para |
|---|---|
| `feat/` | funcionalidade nova |
| `fix/` | correção de comportamento |
| `docs/` | documentação |
| `chore/` | manutenção, repin de versões |
| `refactor/` | reorganização sem mudar comportamento |
| `ci/` | workflows, automação |
| `style/` | formatação, lint |

---

## 5. O commit

### Cadência

- **Commite em todo checkpoint que faz sentido** — no mínimo uma vez por sessão
  de trabalho, de preferência várias. Trabalho não commitado bloqueia colega e
  se perde num crash.
- **Um commit = uma mudança lógica.** Se você precisa da palavra "e" para
  descrever o commit, ele deveria ser dois.

### O formato

A equipe usa **Conventional Commits, em português**:

```
<tipo>: <o que mudou, em minúsculo, sem ponto final>

<corpo: POR QUE mudou, e o que você verificou>
```

Regras do assunto:

- **até ~72 caracteres**, minúsculo, **sem acento** (o histórico inteiro é
  assim — mantém `git log` legível em terminal de placa embarcada por SSH);
- **descreve o efeito**, não o arquivo mexido;
- `!` depois do tipo quando **quebra quem usa** — `fix!:`, `feat!:`.

Bons exemplos, tirados do histórico real:

```
feat: MotionPolicy — COMO o drone vai de um ponto a outro vira uma escolha
fix: o topico de imagem da fase 1, e os modos de pouso e movimento no YAML
fix!: remove a API de gestos, que estava morta
chore: repina o stdstates em v0.4.0
docs: regenera o CONTRATOS.md apos o merge do main na cbr2026
ci: torna Jazzy obrigatorio e separa o lint
```

O que **não** fazer (também do histórico real — é isso que estamos corrigindo):

```
roi na fase3
coloquei o modo landing de px4 e ativei o controle de yaw e de altitude
blackboard needs adjustments on set
ajustando para poder usar o mesmo landing mode na fase 3 da cbr2026
```

### O corpo importa mais do que você acha

O assunto diz *o quê*; o corpo diz **por quê** e **como você sabe que funciona**.
Daqui a seis meses, depurando um voo, o corpo é a única fonte que sobra. Um bom
corpo responde:

1. Qual era o sintoma / a motivação?
2. Por que esta solução, e não a óbvia?
3. **O que foi verificado** — simulação, voo, CI?

```bash
git commit          # abre o editor: assunto, linha em branco, corpo
```

---

## 6. O que nunca vai para o repositório

O `.gitignore` já barra a maior parte, mas confira o `git status` antes de
`git add`:

| Não versionar | Por quê |
|---|---|
| `build/`, `install/`, `log/` | saída do `colcon`, regenerável |
| `src/` (na raiz do `evtol-dev`) | cada um tem repositório próprio |
| `.evtol-profile` | é a escolha **desta** máquina |
| `.vscode/settings.json`, `launch.json` | caminhos absolutos da sua máquina |
| `.venv/` | derivado do `env/<perfil>.yaml` |
| Bags, vídeos, `.pt`, datasets | pesados; repositório de git não é storage |
| Chaves, tokens, senhas, IPs de rede da equipe | os repositórios são **públicos** |

> Quase todos os repositórios da organização são **públicos**. Antes de subir,
> pergunte-se se aquilo pode ser lido por qualquer pessoa da internet.

**Prefira `git add <arquivo>` a `git add -A`.** É como um `build/` inteiro ou uma
credencial entram sem ninguém notar.

---

## 7. O push e o Pull Request

```bash
git push -u origin fix/meu-ajuste     # primeira vez neste branch
git push                              # nas seguintes
```

Depois, o PR — pelo browser ou pelo `gh`:

```bash
gh pr create --fill                   # usa o commit como título e corpo
gh pr create                          # abre o editor, para escrever um resumo melhor
gh pr status                          # como está o seu PR e o CI
gh pr checks                          # o CI, direto no terminal
```

### O que o PR precisa ter

1. **Título no mesmo formato do commit** — ele vira a mensagem do merge.
2. **Uma descrição que dá contexto**: o que muda, por que, e **como foi
   testado** (simulação? voo? qual fase?).
3. **CI verde.** Todo repositório de biblioteca compila em
   `build (humble)` **e** `build (jazzy)`. Os dois são obrigatórios — é o que
   garante que uma biblioteca não virou Humble-only sem ninguém perceber.
   O job de **lint é informativo** e não bloqueia.
4. **Revisão**, onde o repositório exige (tabela na seção 8) — e é boa prática
   pedir mesmo onde não exige.

### O CI reprovou. E agora?

Leia o log antes de mexer. O padrão mais comum de falha nesses repositórios não
é o seu código: é **dependência não declarada**. As imagens do CI são mínimas
(`ros:humble-ros-base`), iguais a uma Jetson recém-instalada — na sua máquina de
desenvolvimento o `ros-humble-desktop` traz dezenas de pacotes de carona e
esconde o problema. Se faltou algo, declare no `package.xml` com a chave certa
do **rosdep** (`eigen`, não `Eigen3`; `python3-tk`, não `python3-tkinter`).

E o CI de cada repositório monta o workspace a partir do `evtol.repos` da `main`
do `evtol-dev` — então uma falha pode vir de um pin lá, não do seu PR. Já
aconteceu.

### O merge

- **Nunca faça merge do próprio PR sem CI verde.**
- Depois do merge, **apague o branch** (o botão aparece no próprio PR).
- Volte para a `main` e puxe: `git checkout main && git pull`.

---

## 8. O que cada repositório exige hoje

Estado real das proteções na organização — vale conferir de novo se alguém
mudar:

| Exigência | Repositórios |
|---|---|
| **PR + 1 aprovação + `build (humble)` e `build (jazzy)` verdes + branch atualizado com a `main`** | `cbr2026`, `stdbt`, `vision_geometry` |
| **PR + CI verde nas duas distros** (aprovação não obrigatória) | `drone_lib`, `stdstates`, `cv_nodes`, `fsm`, `custom_msgs`, `camera_publisher`, `telemetry_handler` |
| **Sem trava técnica** — a regra vale igual, por convenção | `evtol-dev`, `sae2026`, `sim2d`, `slam_bridge`, `maze_geometry`, `ozzy_bridge`, `ensaio_em_voo`, `itajuba2026` |

Em todos: **force push e apagar a `main` estão bloqueados** onde há proteção.
Onde não há, **não faça mesmo assim** — `git push --force` numa branch
compartilhada apaga trabalho de outra pessoa sem aviso.

Nos três da primeira linha, uma aprovação **é descartada** se você empurrar
commits novos depois dela. Peça revisão de novo.

Repositório novo? Copie o CI e ligue a trava:

```bash
mkdir -p src/meu_repo/.github/workflows
cp templates/workflows/build.yml src/meu_repo/.github/workflows/
```

O arquivo **não precisa de edição** — os pacotes são descobertos com
`colcon list`. Depois, em *Settings → Branches*, exija `build (humble)` e
`build (jazzy)`.

---

## 9. Depois do merge — a tag e o pin

**Este é o passo que todo mundo esquece, e é o que faz a sua mudança chegar às
outras máquinas.**

Mergear numa biblioteca **não muda nada** para o resto da equipe: o workspace
não usa a `main` dela, usa a **tag pinada** no `evtol.repos`. Enquanto o pin não
subir, o seu trabalho existe só no GitHub.

O ciclo completo:

```
PR no repositório da lib → CI verde → merge → TAG nova → PR no evtol-dev subindo o pin
```

```bash
# no repositório da biblioteca, já na main atualizada:
git checkout main && git pull
git tag -a v0.5.0 -m "Nota curta do que mudou desde a v0.4.x"
git push origin v0.5.0
```

Qual número subir:

| Bump | Quando | Exemplo |
|---|---|---|
| **Patch** `v0.4.0 → v0.4.1` | correção compatível, mesma API, seguro trocar | bugfix num detector |
| **Minor** `v0.4.0 → v0.5.0` | funcionalidade nova, ou algo que quem usa precisa adotar | método público novo no `Drone` |
| **Major** `v0.x → v1.0` | declaração deliberada de "isto é estável" | ainda não usamos |

Depois, o PR no `evtol-dev`:

```yaml
  stdstates:
    type: git
    url: https://github.com/Equipe-eVTOL-ITA/stdstates.git
    version: v0.5.0   # comentario curto: por que subiu
```

```
chore: repina o stdstates em v0.5.0
```

> **O manifesto só aceita tag ou hash de commit — nunca branch.** Pinar `main`
> traz de volta exatamente o problema do "o que estiver checado out agora" que o
> manifesto veio resolver. O CI do `evtol-dev` reprova pin que não resolve no
> remoto.

E quem recebe o pin novo:

```bash
cd ~/evtol/dev
git pull
vcs import src < evtol.repos     # ⚠️ troca o que está checado out: veja a seção 3 antes
./doctor.sh
```

---

## 10. Regras extras do evtol-dev

O `evtol-dev` não tem código compilável, então o CI dele confere outras coisas.
Se você mexeu na raiz do workspace, o PR pode reprovar por:

| Check | O que quer dizer |
|---|---|
| Sintaxe de `.sh`, `.py`, `.yaml` | algum arquivo não analisa |
| Cada perfil resolve `ros.distro`, `os.python`, `os.release` | você mexeu em `env/` e quebrou a herança dos perfis |
| `--current` funciona | idem |
| Tasks do VS Code coerentes | `tasks.json` cita um `input` que não existe, ou pergunta o mesmo duas vezes |
| `docs/CONTRATOS.md` em dia | você mudou código com bloco-âncora e não regenerou a doc |
| Toda versão do `evtol.repos` existe | pin apontando para tag que não foi empurrada |

Os dois que mais pegam gente:

```bash
python3 scripts/contratos.py       # regenera o CONTRATOS.md (task: contratos: atualizar)
git push origin v0.5.0             # a tag PRECISA estar no remoto antes do PR do pin
```

---

## 11. Quando dá errado

| Situação | O que fazer |
|---|---|
| **Commitei em detached HEAD** | `git switch -c salva-trabalho` ali mesmo, antes de sair |
| **Commitei na `main` local sem querer** | `git branch fix/meu-trabalho` → `git reset --hard origin/main` → `git checkout fix/meu-trabalho` |
| **Commitei na branch errada** | `git log` para achar o hash → `git checkout -b certa` → `git cherry-pick <hash>` → remova da errada |
| **Mensagem de commit ruim, ainda não empurrada** | `git commit --amend` |
| **Mensagem ruim já empurrada** | deixe. Corrija no título do PR — reescrever histórico compartilhado é pior |
| **`git push` recusado (`rejected`)** | alguém empurrou antes: `git pull --rebase` → resolva → `git push` |
| **Push na `main` recusado por proteção** | é o esperado. Crie um branch e abra PR |
| **Commitei `build/` ou uma credencial** | **avise a equipe antes de qualquer coisa**. Credencial vazada em repo público = credencial queimada: revogue primeiro, limpe depois |
| **`vcs import` sumiu com o meu trabalho** | ele não apaga commit: procure com `git -C src/<repo> reflog` |
| **Conflito no merge** | resolva no seu branch (`git pull origin main` no branch, resolva, commite) — nunca no PR do outro |

---

## 12. A cola

```bash
# 1. entrar no repositório certo e sair do detached
cd ~/evtol/dev/src/<repositorio>
git checkout main && git pull
git checkout -b feat/o-que-eu-vou-fazer

# 2. trabalhar, commitando em cada checkpoint
git status                 # confira o que vai entrar
git add <arquivos>         # nominalmente, não -A
git commit                 # tipo: assunto sem acento + corpo com o porquê

# 3. subir e abrir o PR
git push -u origin feat/o-que-eu-vou-fazer
gh pr create
gh pr checks               # espere build (humble) e build (jazzy) verdes

# 4. depois do merge, se for biblioteca: tag + pin
git checkout main && git pull
git tag -a v0.X.0 -m "o que mudou" && git push origin v0.X.0
# e um PR no evtol-dev subindo o version: do evtol.repos
```

**As cinco regras que resolvem 90% dos problemas:**

1. `git checkout main` **antes** de mexer em qualquer repo de `src/`.
2. Branch sempre; `main` nunca recebe commit direto.
3. Um commit = uma mudança; assunto `tipo: o que mudou`; corpo com o porquê.
4. PR com CI verde nas duas distros — Humble **e** Jazzy.
5. Mergeou numa lib? **Tag + pin no `evtol.repos`**, ou ninguém recebe.

---

*Base normativa: `docs/ARCHITECTURE.md` (Versioning Policy, Git Workflow
Practices, Golden Rules) e `docs/GUIA.md` (seções 3, 6 e 7).*
