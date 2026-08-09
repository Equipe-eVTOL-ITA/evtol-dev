# evtol-dev

Meta repository for the eVTOL ITA workspace — documentation, templates, and guides.

This is **not** a ROS2 package. It is intentionally ignored by `colcon build`.

## Contents

| File | Description |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Workspace architecture, dependency model, and golden rules |
| [SETUP.md](SETUP.md) | Step-by-step setup guide for new team members |
| [doctor.sh](doctor.sh) | Verifica se a máquina bate com o perfil de ambiente declarado |
| [env/](env/) | Perfis de ambiente — o que o `.repos` não consegue pinar |
| [templates/scripts/](templates/scripts/) | Template scripts to bootstrap new competition repos |

## Verificação de ambiente (`doctor.sh`)

```bash
./doctor.sh --list                      # perfis disponíveis
./doctor.sh --profile desktop-humble    # verifica esta máquina
echo desktop-humble > .evtol-profile    # fixa o perfil; depois basta ./doctor.sh
```

Sai com código 0 se o ambiente confere e 1 se não — por isso pode ser usado como
portão dentro do `setup.sh` e do CI.

### Por que isso existe

Um manifesto `.repos` garante que todo mundo tem o mesmo **código**. Ele não tem
como garantir que todo mundo tem o mesmo **ambiente**, e é sempre aí que nascem
os bugs caros — porque essa classe de erro não produz mensagem de erro. Ela
produz "não funciona e ninguém sabe por quê".

Três casos reais do time, todos cobertos por `env/desktop-humble.yaml`:

| Sintoma que apareceu | Causa real |
|---|---|
| Nenhum tópico do Gazebo chegava no ROS | `ros-humble-ros-gz-*` (compilado contra **Fortress**) instalado no lugar de `ros-humble-ros-gzgarden-*`. O PX4 v1.15.4 instala Gazebo **Garden**; o bridge tem que ser da mesma safra. Instala sem erro, roda sem erro, não enxerga nada. |
| Código parou de funcionar sem ninguém ter mexido | Distro do ROS trocado (Humble ↔ Jazzy) sem aviso. Há um drone com Jetson (Humble) e outro com Raspberry Pi (Jazzy). |
| Precisava editar o código à mão depois de subir pro drone | Versão de OpenCV diferente entre a máquina de dev e o drone — funções com nome levemente diferente entre as versões. |

### Como editar um perfil

Mude um valor em `env/<perfil>.yaml` **somente** quando a mudança for
intencional e validada em simulação ou voo. Um valor alterado por acidente aqui
é exatamente o bug que este arquivo existe para impedir. Os comentários
`# verificado:` registram a versão exata observada numa máquina comprovadamente
funcional; o valor enforçado é um glob um pouco mais frouxo, para não quebrar a
cada patch do apt — o que fica pinado com precisão é sempre o que distingue uma
variante **incompatível** de uma compatível.

## How to use the templates

When creating a new competition repository:

```bash
# 1. Create the competition repo
mkdir -p src/my_competition/scripts

# 2. Copy templates
cp src/evtol-dev/templates/scripts/*.sh src/my_competition/scripts/

# 3. Customize:
#    - simulate.sh: add your Gazebo worlds and drone poses
#    - build.sh: add your package targets
#    - agent.sh: usually no changes needed
```
