# Modelos e Mundos Customizados do Gazebo

Como os modelos (`x500_sae`, `x500_cbr2026`, ...) e mundos (`sae1_26`,
`cbr2026_fase1`, ...) da equipe chegam até a simulação.

## Instalação

Uma vez por máquina:

```bash
git clone https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git ~/PX4-gazebo-models
```

**É só isso.** Não há symlink a criar, nem passo a repetir quando um modelo
novo entra no repositório.

> A versão (commit) do repositório é pinada em `env/<perfil>.yaml` e conferida
> pelo `doctor.sh`. Se você atualizar o repositório, atualize o pin no mesmo
> PR: mundo diferente é resultado diferente.

## Como funciona

Modelos e mundos são resolvidos de formas **diferentes** pelo PX4, e vale
saber qual é qual:

| | Como é encontrado |
|---|---|
| **Modelos** | O Gazebo procura no `GZ_SIM_RESOURCE_PATH`. O `simulate.sh` põe `~/PX4-gazebo-models/models` **na frente**, então o repositório da equipe tem prioridade — e pode até sobrescrever um modelo do próprio PX4. |
| **Mundos** | O PX4 monta um caminho absoluto dentro da árvore dele: `gz sim -s "${PX4_GZ_WORLDS}/${mundo}.sdf"`. O arquivo precisa aparecer lá. O `simulate.sh` cria o link do mundo que vai lançar, sozinho. |

Ou seja: **você não precisa fazer nada além de clonar.** Adicionou um modelo?
Ele já é encontrado. Adicionou um mundo? O `simulate.sh` linka na primeira vez
que você o usa.

### Por que a ordem do path importa

Isto já causou bug. Enquanto a árvore do PX4 vinha primeiro no
`GZ_SIM_RESOURCE_PATH`, uma cópia antiga de modelo escondia a deste
repositório — a versão que rodava não era a versionada, e ninguém percebia.
Foi assim que a `vertical_camera` ficou com duas poses diferentes e o
`sae2_26.sdf` ficou defasado por meses.

## Se a sua máquina veio do método antigo

Até 2026-08, dois métodos conviveram: trocar o `remote` do submódulo
`Tools/simulation/gz` do PX4 para o fork da equipe, **e** criar symlinks. O
resultado era duplicação — os modelos existiam em dois lugares, e o do PX4
ganhava.

Para voltar ao estado limpo:

```bash
# 1. Restaura o submódulo original do PX4
cd ~/PX4-Autopilot
git submodule sync -- Tools/simulation/gz
git submodule update --init --force Tools/simulation/gz

# 2. Remove o que sobrou (cópias e symlinks da era anterior)
git -C Tools/simulation/gz clean -fd models worlds

# 3. Confirme
git -C Tools/simulation/gz status --porcelain   # deve sair vazio
```

> **Antes do passo 2**, confira que nada existe apenas na árvore do PX4:
>
> ```bash
> cd ~/PX4-Autopilot/Tools/simulation/gz
> for i in $(git status --porcelain | awk '{print $2}'); do
>     [ -e ~/PX4-gazebo-models/"${i%/}" ] || echo "SÓ AQUI: $i"
> done
> ```
>
> Se listar algo, leve para `~/PX4-gazebo-models` antes de limpar.

Um detalhe do método antigo que gerava lixo: o `ln -sfn origem destino` com o
destino já existindo como diretório real não substitui — cria o link **dentro**
dele. Ficavam coisas como `models/x500/x500 -> .../models/x500/`.

## Verificação

```bash
cd ~/evtol/dev
bash src/sae2026/scripts/simulate.sh sae1
```

Espere ver o modelo no mundo e, no console, `INFO [commander] Ready for
takeoff!`.

Se o mundo ou o modelo não for encontrado, o `simulate.sh` para antes de
chamar o PX4 e diz exatamente o que falta — em vez de deixar o PX4 falhar com
`Service call timed out. Check GZ_SIM_RESOURCE_PATH`, que aponta para o lugar
errado.
