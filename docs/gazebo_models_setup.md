# Modelos e Mundos Customizados do Gazebo

Como instalar os modelos (`x500_sae`, `x500_dual_cam`, ...) e mundos
(`sae1_26`, `sae2_26`, `sae3_26`, ...) da equipe dentro do PX4.

> **Este é o método oficial.** Ele substitui a instrução que existia na §4 do
> `SETUP.md` (trocar o `remote` de `Tools/simulation/gz` para o fork da
> equipe). Os dois métodos coexistiram por um tempo, e o resultado foi uma
> máquina com **as duas coisas ao mesmo tempo** — parte dos mundos vindo de um
> checkout e parte de outro, em commits diferentes do mesmo repositório. Veja
> *Se a sua máquina já tem o método antigo* no fim.

---

## Por que não basta variável de ambiente

O `rcS` do PX4 força o Gazebo a procurar os `.sdf` dentro da própria árvore do
PX4 (`~/PX4-Autopilot/Tools/simulation/gz/`). Exportar `GZ_SIM_RESOURCE_PATH`
apontando para outro lugar não é suficiente: o PX4 continua lendo de lá.

Por isso os modelos precisam *aparecer* dentro daquela pasta. Fazemos isso com
**symlinks**, para que o repositório dos modelos continue sendo um repositório
normal, atualizável com `git pull`, sem se misturar ao submódulo do PX4.

---

## Instalação

Uma vez por máquina:

```bash
# 1. Clone o repositório de modelos da equipe
cd ~
git clone https://github.com/Equipe-eVTOL-ITA/PX4-gazebo-models.git

# 2. Aponte os modelos para dentro da árvore do PX4
for d in ~/PX4-gazebo-models/models/*/; do
    ln -sfn "$d" ~/PX4-Autopilot/Tools/simulation/gz/models/"$(basename "$d")"
done

# 3. Idem para os mundos
ln -sf ~/PX4-gazebo-models/worlds/*.sdf ~/PX4-Autopilot/Tools/simulation/gz/worlds/
```

A partir daí, atualizar **modelos e mundos que já existiam** é só:

```bash
git -C ~/PX4-gazebo-models pull
```

Os symlinks apontam para os arquivos, então o conteúdo novo aparece sozinho.

> **Mas arquivo NOVO não ganha symlink sozinho.** Os symlinks são criados uma
> vez; se você (ou alguém) adicionar um mundo ou modelo ao repositório depois
> disso, ele existe em `~/PX4-gazebo-models` e **não** dentro do PX4. O sintoma
> é o PX4 falhar apontando para o lugar errado:
>
> ```
> Unable to find or download file
> ERROR [gz_bridge] Service call timed out. Check GZ_SIM_RESOURCE_PATH is set correctly.
> ```
>
> A mensagem manda olhar o `GZ_SIM_RESOURCE_PATH`, mas a causa é o symlink que
> falta. O `simulate.sh` dos templates confere isso antes de chamar o PX4 e
> avisa com o comando pronto.
>
> **Depois de adicionar qualquer coisa nova, refaça os symlinks** — os passos 2
> e 3 são idempotentes, pode rodar quantas vezes quiser:
>
> ```bash
> for d in ~/PX4-gazebo-models/models/*/; do
>     ln -sfn "$d" ~/PX4-Autopilot/Tools/simulation/gz/models/"$(basename "$d")"
> done
> ln -sf ~/PX4-gazebo-models/worlds/*.sdf ~/PX4-Autopilot/Tools/simulation/gz/worlds/
> ```

> A versão (commit) de `~/PX4-gazebo-models` é pinada em `env/<perfil>.yaml` e
> conferida pelo `doctor.sh`. Se você atualizar o repositório, atualize o pin no
> mesmo PR: mundo diferente é resultado diferente.

---

## Verificação

```bash
cd ~/evtol/dev
bash src/sae2026/scripts/simulate.sh sae1
```

Espere ver o modelo `x500_sae` no mundo e, no console:

```
INFO  [commander] Ready for takeoff!
```

Confira também que os mundos em uso são mesmo symlinks (e não cópias antigas
escondendo os atuais):

```bash
ls -l ~/PX4-Autopilot/Tools/simulation/gz/worlds/sae*_26.sdf
```

Todos devem aparecer como `-> /home/<você>/PX4-gazebo-models/worlds/...`.

---

## Se a sua máquina já tem o método antigo

Sintoma: `Tools/simulation/gz` tem o fork da equipe como `origin`, e alguns
mundos são arquivos reais em vez de symlinks. O risco é concreto — numa máquina
do time foi encontrado exatamente isto:

| Mundo | Origem | Tamanho |
|---|---|---|
| `sae1_26.sdf` | symlink → `~/PX4-gazebo-models` (mai/2026) | atual |
| `sae2_26.sdf` | **arquivo real** do remote trocado (out/2025) | **4064 bytes** |
| `sae3_26.sdf` | symlink → `~/PX4-gazebo-models` (mai/2026) | atual |

O `sae2_26.sdf` do remote trocado tinha **4064 bytes** contra **4315** do
atual: quem rodava `simulate.sh sae2` estava simulando contra um mundo
diferente do que `sae1` e `sae3` usavam, sem nenhum sinal disso.

Para voltar ao estado limpo:

```bash
# 1. Restaure Tools/simulation/gz para o submódulo original do PX4
cd ~/PX4-Autopilot
git submodule update --init --force Tools/simulation/gz

# 2. Refaça os symlinks (passos 2 e 3 da Instalação acima)

# 3. Confirme que não sobrou arquivo real escondendo symlink
ls -l ~/PX4-Autopilot/Tools/simulation/gz/worlds/*.sdf | grep -v '\->'
```

O passo 3 deve não listar nenhum mundo da equipe. Se listar, apague o arquivo e
refaça o symlink daquele mundo.
