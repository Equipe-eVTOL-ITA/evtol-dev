# Como mandar código para o GitHub

**Guia prático para os membros da equipe eVTOL ITA.**

Responde a uma pergunta só: *acabei de mexer num arquivo — o que eu faço para
isso chegar ao GitHub?*

Resposta curta: **a task `git: publicar` do VS Code.** Ela faz o caminho
inteiro. O resto desta página explica o que ela faz e o que só você pode
decidir.

---

## 1. Uma vez por máquina

```bash
git config --global user.name  "Seu Nome Completo"
git config --global user.email "seu-email-do-github@exemplo.com"

sudo apt install gh    # se ainda não tiver
gh auth login          # GitHub.com → HTTPS → autenticar pelo browser
```

Use **o mesmo e-mail cadastrado no GitHub**, senão os commits aparecem sem
rosto. Confira com `gh auth status`.

---

## 2. Onde o seu arquivo mora

**Não existe "o repositório da equipe".** São dezesseis, e quem decide para
onde você commita é **onde está o arquivo que você editou**.

| Você mexeu em... | O repositório é |
|---|---|
| Lógica de uma fase da competição | `cbr2026`, `sae2026`, `itajuba2026` |
| Um estado reutilizável de FSM | `stdstates` |
| Um nó de visão / detector | `cv_nodes` |
| Uma capacidade do veículo (PX4) | `drone_lib` |
| Um tipo de mensagem novo | `custom_msgs` |
| Manifesto, perfis, scripts da raiz, tasks, docs do workspace | `evtol-dev` |

A task pergunta qual é — e é a única coisa que ela não consegue adivinhar.

> **`src/` é ignorado pelo git do `evtol-dev`**, de propósito: cada pasta ali
> dentro tem repositório próprio. `git add -A` na raiz **não** leva junto uma
> mudança em `src/stdstates/`.

Para ver onde há trabalho solto em todo o workspace: `./doctor.sh`, ou a task
**perfil**.

---

## 3. Publicar

Task **`git: publicar`** (ou `scripts/git_push.sh` no terminal). Ela:

1. **cria o branch**, se você estiver na `main` — o nome sai da sua mensagem
   (`fix: o pouso ultrapassa` → `fix/o-pouso-ultrapassa`);
2. **commita** o que está no diretório de trabalho;
3. **empurra**;
4. **abre o pull request**;
5. **liga o auto-merge** — o PR se mergeia sozinho quando o CI ficar verde.

Você não precisa esperar nem voltar depois para clicar em nada.

**"sem CI"** acrescenta `[skip ci]` e nenhum workflow roda. Nesse modo o
auto-merge não é ligado (ele espera o CI, que não vai rodar) e o PR fica aberto
para você. Use quando forem vários commits seguidos e só o último precisar ser
verificado — sabendo que a única verificação daquele push foi a sua.

### O que ainda é seu

- **A mensagem.** Formato `tipo: o que mudou` — minúsculo, sem acento, até ~72
  caracteres, descrevendo o **efeito** e não o arquivo. Tipos: `feat` `fix`
  `docs` `chore` `refactor` `ci` `style`. Use `!` quando quebra quem usa
  (`fix!:`). Um commit = uma mudança lógica: se precisa da palavra "e", são
  dois.
- **Commitar com frequência.** No mínimo uma vez por sessão. Trabalho não
  commitado bloqueia colega e se perde num crash.
- **Pedir revisão.** Não é mais obrigatória em repositório nenhum — o que
  significa que ela agora depende de você pedir. Vale a pena em tudo que voa.

Se o CI reprovar, leia o log antes de mexer. A falha mais comum não é o seu
código: é **dependência não declarada**. As imagens do CI são mínimas, iguais a
uma Jetson recém-instalada; a sua máquina tem `ros-humble-desktop`, que traz
dezenas de pacotes de carona e esconde o problema. Declare no `package.xml` com
a chave certa do **rosdep** (`eigen`, não `Eigen3`; `python3-tk`, não
`python3-tkinter`).

---

## 4. Receber o trabalho dos outros

Task **`git: atualizar tudo`**, ou:

```bash
cd ~/evtol/dev && git pull --ff-only && vcs pull src
```

O `evtol.repos` acompanha a **`main`** de cada repositório da equipe. Isso quer
dizer que **um merge chega em todo mundo imediatamente** — não há mais tag para
criar nem pin para subir depois. Também quer dizer que uma quebra chega junto:
se o workspace parar de compilar sem você ter mexido em nada, olhe o
[build noturno](https://github.com/Equipe-eVTOL-ITA/evtol-dev/actions/workflows/noturno.yml)
antes de procurar no seu código.

---

## 5. Antes de competir: congelar

"A `main` de hoje" não é resposta aceitável para *o que exatamente voou*. Na
máquina onde você acabou de compilar e testar:

```bash
scripts/congelar.sh          # task: voo: congelar
```

Isso grava o `voo.repos` com a revisão exata de cada repositório. Na Jetson ou
na Raspberry:

```bash
./setup.sh --manifesto voo.repos
```

Se o voo merece ficar registrado, commite o arquivo com nome próprio —
`cbr2026-final.repos` — e a pergunta "o que voou na final" passa a ter resposta
para sempre.

---

## 6. O que nunca vai para o repositório

| Não versionar | Por quê |
|---|---|
| `build/`, `install/`, `log/` | saída do `colcon`, regenerável |
| `src/` (na raiz do `evtol-dev`) | cada um tem repositório próprio |
| `.evtol-profile` | é a escolha **desta** máquina |
| `.vscode/settings.json`, `launch.json` | caminhos absolutos da sua máquina |
| `.venv/` | derivado do `env/<perfil>.yaml` |
| Bags, vídeos, `.pt`, datasets | repositório de git não é storage |
| Chaves, tokens, senhas, IPs da equipe | os repositórios são **públicos** |

> Quase todos os repositórios são **públicos**. Antes de subir, pergunte-se se
> aquilo pode ser lido por qualquer pessoa da internet.

---

## 7. Quando dá errado

| Situação | O que fazer |
|---|---|
| **Commitei na `main` local sem querer** | `git branch fix/meu-trabalho` → `git reset --hard origin/main` → `git checkout fix/meu-trabalho` |
| **Mensagem ruim, ainda não empurrada** | `git commit --amend` |
| **Mensagem ruim já empurrada** | deixe; corrija no título do PR |
| **`git push` recusado (`rejected`)** | `git pull --rebase` → resolva → `git push` |
| **Push na `main` recusado** | é o esperado: a task cria o branch para você |
| **Commitei `build/` ou uma credencial** | **avise a equipe antes de tudo.** Credencial em repo público = credencial queimada: revogue primeiro, limpe depois |
| **Conflito no merge** | resolva no seu branch, nunca no PR do outro |
| **Estou em detached HEAD** | `git switch -c salva-trabalho` ali mesmo. Não deveria acontecer: o manifesto pina `main` |

---

## 8. A política, em cinco linhas

Todo repositório da organização exige a mesma coisa, sem exceção:

- **pull request** — nada entra na `main` direto;
- **`build (humble)` verde** — o único check obrigatório;
- **sem force push, sem apagar a `main`**;
- **aprovação não é obrigatória** — revisão é pedida, não é portão;
- **o branch é apagado sozinho** depois do merge.

O Jazzy e a integração do workspace inteiro são conferidos uma vez por dia pelo
workflow `noturno`, que abre issue se quebrar.

Repositório novo? `cp templates/workflows/build.yml src/meu_repo/.github/workflows/`
(o arquivo não precisa de edição — os pacotes são descobertos com `colcon
list`), e `scripts/proteger.sh meu_repo` aplica a política acima.

---

## 9. A cola

```bash
# publicar (ou a task "git: publicar")
bash scripts/git_push.sh <repo> "fix: o que mudou" "com CI"

# receber o trabalho dos outros
git pull --ff-only && vcs pull src

# congelar, antes de competir
scripts/congelar.sh
```

**As três regras que resolvem quase tudo:**

1. Publique pela task, e commite várias vezes por sessão.
2. `tipo: o que mudou` — sem acento, descrevendo o efeito.
3. Vai voar? **Congele** — `voo.repos` é o que a Jetson deve importar.

---

*Base normativa: `docs/ARCHITECTURE.md` (Versioning Policy, Git Workflow
Practices, Golden Rules).*
