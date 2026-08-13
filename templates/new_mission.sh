#!/usr/bin/env bash
# =============================================================================
# new_mission.sh — cria um pacote de missão completo e já compilável.
# =============================================================================
#
#   cd ~/evtol/dev/src/<competicao>
#   ~/evtol/dev/templates/new_mission.sh fase1
#
# Gera a estrutura que TODA fase de competição tem, para você começar da lógica
# da missão em vez de do boilerplate:
#
#   fase1/
#   ├── package.xml            deps já declaradas
#   ├── CMakeLists.txt         alvo, includes e install de launch/config
#   ├── src/fase1.cpp          FSM + Node completos: blackboard, parâmetros,
#   │                          ARMING → TAKEOFF → LANDING já ligados, timer de
#   │                          20 Hz, publicação de trajetória e o main com
#   │                          executor multi-thread
#   ├── include/fase1/states/  onde entram os estados desta missão
#   │   └── example_state.hpp  um estado comentado, para copiar
#   ├── config/                simulation.yaml e flight.yaml
#   └── launch/                simulation.launch.py e flight.launch.py
#
# O pacote gerado COMPILA E VOA (arma, sobe, pousa) sem você escrever nada.
# A partir daí é só acrescentar estados.
# =============================================================================

set -euo pipefail

die() { echo "ERRO: $*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Uso: new_mission.sh <nome_da_missao> [--engine fsm|bt]

  Rode de dentro do repositório da competição, ex.:

      cd ~/evtol/dev/src/cbr2027
      ~/evtol/dev/templates/new_mission.sh fase1
      ~/evtol/dev/templates/new_mission.sh fase4 --engine bt

  O nome deve ser um identificador válido de pacote ROS: minúsculas,
  dígitos e underscore, começando por letra. Ex.: fase1, missao_2, fase_final

  --engine escolhe como a missão é modelada:

    fsm   Máquina de estados (PADRÃO). Estados nomeados e transições
          explícitas entre eles. É o que o time sempre usou.

    bt    Behavior Tree. A lógica vive num XML editável, e a composição
          -- Sequence, Fallback, decoradores -- substitui as transições.
          Rende melhor quando há muitas condições de recuperação, e dá o
          Groot2 para ver a árvore ao vivo.

  As duas geram uma fase que COMPILA E VOA. A escolha é por fase: uma mesma
  competição pode ter fases nos dois motores.
EOF
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
case "${1}" in -h|--help) usage; exit 0 ;; esac

PKG="$1"; shift

ENGINE="fsm"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine)
            [[ $# -ge 2 ]] || die "--engine exige um valor: fsm ou bt"
            ENGINE="$2"; shift 2 ;;
        --engine=*) ENGINE="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "argumento desconhecido: $1" ;;
    esac
done

[[ "$ENGINE" == "fsm" || "$ENGINE" == "bt" ]] || \
    die "--engine aceita 'fsm' ou 'bt', não '$ENGINE'."
[[ "$PKG" =~ ^[a-z][a-z0-9_]*$ ]] || \
    die "'$PKG' não é um nome válido de pacote ROS (minúsculas, dígitos, underscore, começando por letra)."

# ── Estou no lugar certo? ────────────────────────────────────────────────────
#
# Esta checagem era `[[ -d .git ]]`, e um aviso. Nao servia: a raiz do workspace
# (~/evtol/dev) TAMBEM e um repositorio git -- e o evtol-dev --, entao rodar o
# gerador de la nao disparava aviso nenhum e criava a fase no lugar errado,
# fora de qualquer competicao.
#
# O sinal confiavel e o diretorio PAI se chamar `src`. E a mesma heuristica que
# o env/doctor.py usa para achar a raiz do workspace, e ela distingue
# <ws>/src/cbr2026 (certo) de <ws> (errado) sem ambiguidade.
#
# E erro, nao aviso: uma fase criada no lugar errado nao entra no manifesto, nao
# aparece nas tasks e nao compila. Melhor parar aqui do que descobrir depois.
if [[ "$(basename "$(dirname "$PWD")")" != "src" ]]; then
    cat >&2 <<AJUDA
ERRO: rode este script de dentro do repositorio da COMPETICAO, nao daqui.

  Voce esta em:  $PWD

  O esperado e um diretorio dentro de <workspace>/src/, por exemplo:

      cd ~/evtol/dev/src/cbr2026
      ~/evtol/dev/templates/new_mission.sh $PKG${ENGINE:+ --engine $ENGINE}

  Competicoes disponiveis neste workspace:
AJUDA
    # O criterio de "competicao" e ter scripts/simulate.sh, o MESMO que o
    # scripts/sync_tasks.py usa. Se as duas ferramentas discordassem sobre o
    # que e uma competicao, uma fase criada por este script poderia nunca
    # aparecer nas tasks do VSCode.
    ws_guess="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    achou=0
    if [[ -d "$ws_guess/src" ]]; then
        for d in "$ws_guess"/src/*/; do
            if [[ -f "$d/scripts/simulate.sh" ]]; then
                echo "      $(basename "$d")" >&2
                achou=1
            fi
        done
    fi
    (( achou )) || echo "      (nenhuma encontrada em $ws_guess/src)" >&2
    exit 1
fi

[[ -d .git ]] || echo "AVISO: '$PWD' esta sob src/ mas nao e um repositorio git." >&2
[[ -e "$PKG" ]] && die "'$PKG' já existe aqui. Escolha outro nome ou apague o diretório."

# fase1 -> Fase1 ; missao_2 -> Missao2   (para os nomes de classe)
CLASS="$(echo "$PKG" | awk -F_ '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')"

# Identificação do maintainer. O catkin_pkg REJEITA e-mail inválido, e o erro
# de parse resultante não explica a causa -- por isso pegamos do git.
MAINT_NAME="$(git config user.name  2>/dev/null || true)"; MAINT_NAME="${MAINT_NAME:-eVTOL ITA}"
MAINT_MAIL="$(git config user.email 2>/dev/null || true)"; MAINT_MAIL="${MAINT_MAIL:-evtol@ita.br}"
[[ "$MAINT_MAIL" == *@*.* ]] || die "e-mail do git ('$MAINT_MAIL') não é válido; ajuste com: git config user.email seu@email.com"

COMP="$(basename "$PWD")"

# ── O que muda por motor ─────────────────────────────────────────────────────
# Mantido como variaveis para que os templates abaixo sejam UM so. Duplicar o
# gerador inteiro por motor garantiria que os dois divergissem na primeira
# correcao feita so de um lado.
if [[ "$ENGINE" == "bt" ]]; then
    DEP_XML="  <depend>stdbt</depend>
  <depend>behaviortree_cpp</depend>
  <depend>ament_index_cpp</depend>
  <test_depend>ament_cmake_gtest</test_depend>"
    DEP_CMAKE_FIND="find_package(stdbt REQUIRED)
find_package(behaviortree_cpp REQUIRED)
find_package(ament_index_cpp REQUIRED)"
    DEP_CMAKE_TARGET="  stdbt
  behaviortree_cpp
  ament_index_cpp"
    EXEMPLO_DIR="nodes"
    INSTALL_TREES="install(DIRECTORY trees/ DESTINATION share/\${PROJECT_NAME}/trees)
"
    # O teste da arvore e obrigatorio no motor bt, e o motivo esta no proprio
    # comentario gerado: um nome de no errado no XML NAO e erro de compilacao.
    TESTE_CMAKE="
  find_package(ament_cmake_gtest REQUIRED)
  ament_add_gtest(test_tree test/test_tree.cpp)
  if(TARGET test_tree)
    target_include_directories(test_tree PRIVATE include)
    ament_target_dependencies(test_tree
      rclcpp Eigen3 fsm drone_lib stdstates stdbt behaviortree_cpp
      ament_index_cpp)
  endif()"
else
    DEP_XML=""
    DEP_CMAKE_FIND=""
    DEP_CMAKE_TARGET=""
    EXEMPLO_DIR="states"
    INSTALL_TREES=""
    TESTE_CMAKE=""
fi

mkdir -p "$PKG"/{src,config,launch} "$PKG/include/$PKG/$EXEMPLO_DIR"
[[ "$ENGINE" == "bt" ]] && mkdir -p "$PKG"/{trees,test}

# ---------------------------------------------------------------- package.xml
cat > "$PKG/package.xml" <<EOF
<?xml version="1.0"?>
<?xml-model href="http://download.ros.org/schema/package_format3.xsd" schematypens="http://www.w3.org/2001/XMLSchema"?>
<package format="3">
  <name>$PKG</name>
  <version>0.0.1</version>
  <description>Missão $PKG da competição $COMP</description>
  <maintainer email="$MAINT_MAIL">$MAINT_NAME</maintainer>
  <license>MIT</license>

  <buildtool_depend>ament_cmake</buildtool_depend>

  <!-- Chave do ROSDEP, nao o nome do pacote CMake (Eigen3 nao existe no indice). -->
  <buildtool_depend>eigen3_cmake_module</buildtool_depend>
  <depend>eigen</depend>

  <depend>rclcpp</depend>
  <depend>fsm</depend>
  <depend>drone_lib</depend>
  <depend>stdstates</depend>
$DEP_XML
  <depend>custom_msgs</depend>
  <depend>nav_msgs</depend>
  <depend>geometry_msgs</depend>
  <depend>std_msgs</depend>

  <test_depend>ament_lint_auto</test_depend>
  <test_depend>ament_lint_common</test_depend>

  <export>
    <build_type>ament_cmake</build_type>
  </export>
</package>
EOF

# ------------------------------------------------------------- CMakeLists.txt
cat > "$PKG/CMakeLists.txt" <<EOF
cmake_minimum_required(VERSION 3.8)
project($PKG)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(eigen3_cmake_module REQUIRED)
find_package(Eigen3 REQUIRED)
find_package(fsm REQUIRED)
find_package(drone_lib REQUIRED)
find_package(stdstates REQUIRED)
$DEP_CMAKE_FIND
find_package(custom_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_msgs REQUIRED)

include_directories(include)
include_directories(\${EIGEN3_INCLUDE_DIR})

add_executable($PKG src/$PKG.cpp)

ament_target_dependencies($PKG
  rclcpp
  Eigen3
  fsm
  drone_lib
  stdstates
$DEP_CMAKE_TARGET
  custom_msgs
  nav_msgs
  geometry_msgs
  std_msgs
)

install(TARGETS $PKG DESTINATION lib/\${PROJECT_NAME})
install(DIRECTORY launch/ DESTINATION share/\${PROJECT_NAME}/launch)
install(DIRECTORY config/ DESTINATION share/\${PROJECT_NAME}/config)
$INSTALL_TREES
if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
$TESTE_CMAKE
endif()

ament_package()
EOF

if [[ "$ENGINE" == "fsm" ]]; then
# ------------------------------------------------------------------- main cpp
cat > "$PKG/src/$PKG.cpp" <<EOF
#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <variant>

#include <rclcpp/rclcpp.hpp>
#include "fsm/fsm.hpp"
#include "drone/Drone.hpp"
#include "nav_msgs/msg/path.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"

// Estados padrao, do stdstates -- servem a qualquer missao.
#include "stdstates/arming_state.hpp"
#include "stdstates/takeoff_state.hpp"
#include "stdstates/landing_state.hpp"

// Estados desta missao. Crie em include/$PKG/states/ e inclua aqui.
// #include "$PKG/states/meu_estado.hpp"

/**
 * @brief Maquina de estados da missao $PKG.
 *
 * Ja vem com o ciclo minimo que toda missao tem: armar, decolar, pousar.
 * Para estender, veja os blocos marcados com ACRESCENTE.
 */
class ${CLASS}FSM : public fsm::FSM {
public:
    ${CLASS}FSM(
        std::shared_ptr<Drone> drone,
        const std::map<std::string, std::variant<double, std::string>> &params
    ) : fsm::FSM({"ERROR", "FINISHED"}) {

        // O drone fica na blackboard: todo estado o acessa por aqui.
        this->blackboard_set<std::shared_ptr<Drone>>("drone", drone);

        // Parametros do ROS 2 (vindos do YAML) viram entradas da blackboard.
        for (const auto &[key, value] : params) {
            if (std::holds_alternative<double>(value)) {
                this->blackboard_set<float>(key, static_cast<float>(std::get<double>(value)));
            } else if (std::holds_alternative<std::string>(value)) {
                this->blackboard_set<std::string>(key, std::get<std::string>(value));
            }
        }

        // ========================= ESTADOS =========================
        this->add_state("ARMING",  std::make_unique<ArmingState>());
        this->add_state("TAKEOFF", std::make_unique<TakeoffState>());
        this->add_state("LANDING", std::make_unique<LandingState>());
        // ACRESCENTE aqui os estados desta missao, ex.:
        // this->add_state("SEARCH", std::make_unique<SearchState>());

        // ======================= TRANSICOES ========================
        // Cada linha e: {outcome retornado pelo estado, proximo estado}.
        this->add_transitions("ARMING", {
            {"ARMED", "TAKEOFF"},
            {"ERROR", "ERROR"}
        });

        this->add_transitions("TAKEOFF", {
            // ACRESCENTE: troque "LANDING" pelo primeiro estado da sua missao.
            {"TAKEOFF COMPLETED", "LANDING"},
            {"ERROR", "ERROR"}
        });

        this->add_transitions("LANDING", {
            {"LANDED", "FINISHED"},
            {"ERROR", "ERROR"}
        });

        this->set_initial_state("ARMING");
    }
};

/**
 * @brief No ROS 2 que executa a FSM da missao $PKG.
 *
 * Declara os parametros (sobrescritos pelo YAML no launch), monta a FSM e a
 * executa a 20 Hz.
 */
class ${CLASS}Node : public rclcpp::Node {
public:
    explicit ${CLASS}Node(std::shared_ptr<Drone> drone)
        : rclcpp::Node("${PKG}_node"), drone_(drone) {

        // Valores padrao. O launch sobrescreve com config/simulation.yaml ou
        // config/flight.yaml -- por isso trocar de simulacao para voo e trocar
        // de YAML, nao editar codigo.
        std::map<std::string, std::variant<double, std::string>> default_params = {
            // Decolagem (lidos pelo TakeoffState)
            {"takeoff_height",          -2.5},   // metros, NED: negativo e para cima
            {"max_vertical_velocity",    1.2},
            {"position_tolerance",       0.15},

            // Pouso (lidos pelo LandingState)
            {"landing_velocity_max",     0.5},
            {"landing_velocity_min",     0.15},
            {"max_base_height",          0.5},
            {"landing_timeout",          5.0},

            // Movimento horizontal
            {"max_horizontal_velocity",  1.5},

            // ACRESCENTE aqui os parametros desta missao, e replique-os nos
            // dois YAML de config/.
        };

        auto params = declareAndGetParameters(default_params);

        fsm_ = std::make_unique<${CLASS}FSM>(drone_, params);

        timer_ = this->create_wall_timer(
            std::chrono::milliseconds(50),                 // 20 Hz
            std::bind(&${CLASS}Node::executeFSM, this));

        // Trajetoria para o RViz2 (convertida de NED para ENU).
        path_pub_ = this->create_publisher<nav_msgs::msg::Path>("/drone_trajectory", 10);
        trajectory_.header.frame_id = "map";

        // ACRESCENTE: assinaturas dos nos de visao desta missao. O padrao e o
        // callback escrever na blackboard e os estados apenas lerem de la.
        //
        // cv_sub_ = this->create_subscription<custom_msgs::msg::MinhaDeteccao>(
        //     "minha_deteccao", 10,
        //     std::bind(&${CLASS}Node::cv_callback, this, std::placeholders::_1));

        RCLCPP_INFO(this->get_logger(), "FSM da missao $PKG iniciada");
    }

private:
    void executeFSM() {
        auto pos    = drone_->getLocalPosition();
        auto orient = drone_->getOrientation();

        // NED -> ENU para visualizar no RViz2.
        geometry_msgs::msg::PoseStamped ps;
        ps.header.stamp       = this->now();
        ps.header.frame_id    = "map";
        ps.pose.position.x    =  static_cast<float>(pos.y());   // East  = NED y
        ps.pose.position.y    =  static_cast<float>(pos.x());   // North = NED x
        ps.pose.position.z    = -static_cast<float>(pos.z());   // Up    = -NED z
        ps.pose.orientation.w = 1.0;
        trajectory_.header.stamp = ps.header.stamp;
        trajectory_.poses.push_back(ps);
        path_pub_->publish(trajectory_);

        // Log de estado e posicao a cada 2 s (40 ticks a 20 Hz).
        if (log_counter_++ % 40 == 0) {
            RCLCPP_INFO(this->get_logger(), "[%s] pos=(%.2f, %.2f, %.2f) yaw=%.2f rad",
                        fsm_->get_current_state().c_str(),
                        static_cast<float>(pos.x()),
                        static_cast<float>(pos.y()),
                        static_cast<float>(pos.z()),
                        static_cast<float>(orient[2]));
        }

        if (rclcpp::ok() && !fsm_->is_finished()) {
            fsm_->execute();
        } else {
            RCLCPP_INFO(this->get_logger(), "FSM terminou com: %s",
                        fsm_->get_fsm_outcome().c_str());
            rclcpp::shutdown();
        }
    }

    /// Declara cada parametro com seu padrao e le o valor efetivo.
    std::map<std::string, std::variant<double, std::string>> declareAndGetParameters(
        const std::map<std::string, std::variant<double, std::string>> &defaults) {

        std::map<std::string, std::variant<double, std::string>> result;
        for (const auto &[name, default_value] : defaults) {
            if (std::holds_alternative<double>(default_value)) {
                this->declare_parameter(name, std::get<double>(default_value));
                result[name] = this->get_parameter(name).as_double();
            } else if (std::holds_alternative<std::string>(default_value)) {
                this->declare_parameter(name, std::get<std::string>(default_value));
                result[name] = this->get_parameter(name).as_string();
            }
        }
        return result;
    }

    std::shared_ptr<Drone> drone_;
    std::unique_ptr<${CLASS}FSM> fsm_;
    rclcpp::TimerBase::SharedPtr timer_;
    rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr path_pub_;
    nav_msgs::msg::Path trajectory_;
    int log_counter_ = 0;
};

int main(int argc, const char *argv[]) {
    rclcpp::init(argc, argv);

    // O Drone JA sobe o proprio executor e a propria thread de spin no
    // construtor (veja drone_lib/src/Drone.cpp). Adiciona-lo a um executor
    // aqui lanca em tempo de execucao:
    //
    //     terminate called after throwing an instance of 'std::runtime_error'
    //       what():  Node '/Drone' has already been added to an executor.
    //
    // Por isso so o no da missao entra no executor deste main.
    auto drone        = std::make_shared<Drone>();
    auto mission_node = std::make_shared<${CLASS}Node>(drone);

    rclcpp::executors::MultiThreadedExecutor executor;
    executor.add_node(mission_node);
    executor.spin();

    rclcpp::shutdown();
    return 0;
}
EOF
else

# ------------------------------------------------------- main cpp (motor BT)
cat > "$PKG/src/$PKG.cpp" <<EOF
#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <variant>

#include <Eigen/Eigen>

#include <rclcpp/rclcpp.hpp>
#include <ament_index_cpp/get_package_share_directory.hpp>

#include <behaviortree_cpp/bt_factory.h>
#include <behaviortree_cpp/loggers/groot2_publisher.h>

#include "fsm/fsm.hpp"
#include "drone/Drone.hpp"
#include "stdbt/registrar.hpp"

#include "nav_msgs/msg/path.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"

// Nos desta missao. Crie em include/$PKG/nodes/ e inclua aqui.
// #include "$PKG/nodes/meu_no.hpp"

/**
 * @brief Missao $PKG, modelada como Behavior Tree.
 *
 * A DIFERENCA PARA UMA FSM, em uma frase: aqui nao ha transicoes nomeadas. A
 * ESTRUTURA da arvore -- Sequence, Fallback, decoradores -- faz o papel delas.
 *
 *   Sequence   executa os filhos em ordem; para no primeiro que falhar
 *   Fallback   tenta os filhos em ordem; para no primeiro que der certo
 *   Retry, Timeout, Inverter, ...  decoradores, que modificam um filho
 *
 * A arvore vive em trees/$PKG.xml e e instalada no share/ do pacote. Trocar a
 * logica da missao e editar esse XML e relancar -- sem recompilar. E e o que
 * permite abrir a arvore no Groot2 e ver os nos piscando enquanto o drone voa.
 */
class ${CLASS}Node : public rclcpp::Node {
public:
    explicit ${CLASS}Node(std::shared_ptr<Drone> drone)
        : rclcpp::Node("${PKG}_node"), drone_(drone) {

        // Valores padrao. O launch sobrescreve com config/simulation.yaml ou
        // config/flight.yaml -- por isso trocar de simulacao para voo e trocar
        // de YAML, nao editar codigo.
        std::map<std::string, std::variant<double, std::string>> default_params = {
            // Decolagem
            {"takeoff_height",          -2.5},   // metros, FRD: negativo e para cima
            {"max_vertical_velocity",    1.2},
            {"position_tolerance",       0.15},

            // Pouso
            {"landing_velocity_max",     0.5},
            {"landing_velocity_min",     0.15},
            {"max_base_height",         -0.2},

            // Movimento horizontal
            {"max_horizontal_velocity",  1.5},

            // Qual arvore carregar, relativa a share/$PKG/trees/. Os dois
            // perfis podem apontar para arvores diferentes -- e uma das razoes
            // de a arvore ser um arquivo e nao codigo.
            {"tree_file",                std::string("$PKG.xml")},

            // Porta do Groot2. 0 desliga.
            //
            // Com ela ligada, abra o Groot2, conecte nesta porta e veja a
            // arvore ao vivo: qual no esta RUNNING, qual falhou, o valor de
            // cada porta. E a maior vantagem pratica da BT sobre a FSM na hora
            // de depurar.
            {"groot2_port",           1667.0},

            // ACRESCENTE aqui os parametros desta missao, e replique-os nos
            // dois YAML de config/.
        };

        auto params = declareAndGetParameters(default_params);

        // A blackboard da FSM continua sendo a fonte de parametros.
        //
        // Os estados do stdstates leem dela, e o adaptador do stdbt os executa
        // sem modificacao. O efeito pratico e que esta missao usa os MESMOS
        // YAML que uma missao em FSM usaria.
        //
        // Os parametros entram como FLOAT, nunca double: fsm::Blackboard faz
        // cast sem checagem, e gravar double para ler float devolve lixo.
        for (const auto &[key, value] : params) {
            if (std::holds_alternative<double>(value)) {
                blackboard_.set<float>(key, static_cast<float>(std::get<double>(value)));
            } else if (std::holds_alternative<std::string>(value)) {
                blackboard_.set<std::string>(key, std::get<std::string>(value));
            }
        }
        blackboard_.set<std::shared_ptr<Drone>>("drone", drone_);

        // ======================= ARVORE =======================
        BT::BehaviorTreeFactory factory;
        stdbt::registerAll(factory);
        // ACRESCENTE aqui os nos desta missao, ex.:
        // factory.registerNodeType<MeuNo>("MeuNo");

        auto bt_blackboard = BT::Blackboard::create();
        bt_blackboard->set(stdbt::kFsmBlackboardKey, &blackboard_);

        const auto arquivo = std::get<std::string>(params.at("tree_file"));
        const auto caminho =
            ament_index_cpp::get_package_share_directory("$PKG") + "/trees/" + arquivo;

        try {
            tree_ = std::make_unique<BT::Tree>(
                factory.createTreeFromFile(caminho, bt_blackboard));
        } catch (const std::exception &e) {
            // Nome de no errado no XML NAO e erro de compilacao: aparece aqui.
            // O test/test_tree.cpp existe para pegar isso no CI, antes do voo.
            RCLCPP_FATAL(this->get_logger(),
                         "nao consegui carregar a arvore '%s': %s", caminho.c_str(), e.what());
            throw;
        }

        RCLCPP_INFO(this->get_logger(), "arvore carregada de %s", caminho.c_str());

        const int porta = static_cast<int>(std::get<double>(params.at("groot2_port")));
        if (porta > 0) {
            groot_ = std::make_unique<BT::Groot2Publisher>(*tree_, porta);
            RCLCPP_INFO(this->get_logger(), "Groot2 escutando na porta %d", porta);
        }

        timer_ = this->create_wall_timer(
            std::chrono::milliseconds(50),                 // 20 Hz
            std::bind(&${CLASS}Node::tick, this));

        path_pub_ = this->create_publisher<nav_msgs::msg::Path>("/drone_trajectory", 10);
        trajectory_.header.frame_id = "map";

        RCLCPP_INFO(this->get_logger(), "missao $PKG iniciada (Behavior Tree)");
    }

private:
    void tick() {
        auto pos    = drone_->getLocalPosition();
        auto orient = drone_->getOrientation();

        // FRD -> ENU para visualizar no RViz2.
        geometry_msgs::msg::PoseStamped ps;
        ps.header.stamp       = this->now();
        ps.header.frame_id    = "map";
        ps.pose.position.x    =  static_cast<float>(pos.y());
        ps.pose.position.y    =  static_cast<float>(pos.x());
        ps.pose.position.z    = -static_cast<float>(pos.z());
        ps.pose.orientation.w = 1.0;
        trajectory_.header.stamp = ps.header.stamp;
        trajectory_.poses.push_back(ps);
        path_pub_->publish(trajectory_);

        if (log_counter_++ % 40 == 0) {
            RCLCPP_INFO(this->get_logger(), "pos=(%.2f, %.2f, %.2f) yaw=%.2f rad",
                        static_cast<float>(pos.x()),
                        static_cast<float>(pos.y()),
                        static_cast<float>(pos.z()),
                        static_cast<float>(orient[2]));
        }

        if (!rclcpp::ok() || terminou_) {
            return;
        }

        // tickOnce(), NUNCA tickWhileRunning().
        //
        // O tickWhileRunning -- que e o exemplo da documentacao oficial --
        // BLOQUEIA ate a arvore terminar. Dentro do callback de um timer isso
        // congela o executor: a telemetria para, a visao para, e o no fica sem
        // responder enquanto o drone voa.
        //
        // O timer ja da o ritmo, do mesmo jeito que da para a FSM.
        const BT::NodeStatus status = tree_->tickOnce();

        if (status != BT::NodeStatus::RUNNING) {
            terminou_ = true;
            RCLCPP_INFO(this->get_logger(), "arvore terminou com: %s",
                        BT::toStr(status).c_str());
            rclcpp::shutdown();
        }
    }

    /// Declara cada parametro com seu padrao e le o valor efetivo.
    std::map<std::string, std::variant<double, std::string>> declareAndGetParameters(
        const std::map<std::string, std::variant<double, std::string>> &defaults) {

        std::map<std::string, std::variant<double, std::string>> result;
        for (const auto &[name, default_value] : defaults) {
            if (std::holds_alternative<double>(default_value)) {
                this->declare_parameter(name, std::get<double>(default_value));
                result[name] = this->get_parameter(name).as_double();
            } else if (std::holds_alternative<std::string>(default_value)) {
                this->declare_parameter(name, std::get<std::string>(default_value));
                result[name] = this->get_parameter(name).as_string();
            }
        }
        return result;
    }

    std::shared_ptr<Drone> drone_;
    fsm::Blackboard blackboard_;
    std::unique_ptr<BT::Tree> tree_;
    std::unique_ptr<BT::Groot2Publisher> groot_;
    rclcpp::TimerBase::SharedPtr timer_;
    rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr path_pub_;
    nav_msgs::msg::Path trajectory_;
    int log_counter_ = 0;
    bool terminou_ = false;
};

int main(int argc, const char *argv[]) {
    rclcpp::init(argc, argv);

    // O Drone JA sobe o proprio executor e a propria thread de spin no
    // construtor. Adiciona-lo a um executor aqui lanca em tempo de execucao:
    //
    //     what():  Node '/Drone' has already been added to an executor.
    //
    // Por isso so o no da missao entra no executor deste main.
    auto drone        = std::make_shared<Drone>();
    auto mission_node = std::make_shared<${CLASS}Node>(drone);

    rclcpp::executors::MultiThreadedExecutor executor;
    executor.add_node(mission_node);
    executor.spin();

    rclcpp::shutdown();
    return 0;
}
EOF
fi

if [[ "$ENGINE" == "fsm" ]]; then
# ------------------------------------------------------- estado de exemplo
cat > "$PKG/include/$PKG/states/example_state.hpp" <<EOF
#ifndef ${PKG^^}__STATES__EXAMPLE_STATE_HPP_
#define ${PKG^^}__STATES__EXAMPLE_STATE_HPP_

#include <string>
#include <memory>

#include "fsm/state.hpp"
#include "drone/Drone.hpp"

/**
 * @brief Modelo de estado desta missao. Copie este arquivo para criar os seus.
 *
 * Um estado tem tres partes:
 *   on_enter  roda UMA vez ao entrar. Leia parametros e guarde o alvo aqui.
 *   act       roda a cada tick (20 Hz). Devolva "" para continuar no estado,
 *             ou o nome de um outcome para transitar.
 *   on_exit   roda UMA vez ao sair (opcional).
 *
 * Todo dado compartilhado passa pela blackboard -- nunca por variavel global
 * nem por ponteiro entre estados.
 */
class ExampleState : public fsm::State {
public:
    ExampleState() : fsm::State() {}

    void on_enter(fsm::Blackboard &blackboard) override {
        drone_ = *blackboard.get<std::shared_ptr<Drone>>("drone");
        if (drone_ == nullptr) return;

        drone_->log("");
        drone_->log("STATE: EXAMPLE");

        // Parametros vem do YAML, via blackboard. NUNCA escreva o numero aqui.
        // max_velocity_ = *blackboard.get<float>("max_horizontal_velocity");

        start_ = drone_->getLocalPosition();
    }

    std::string act(fsm::Blackboard &blackboard) override {
        (void)blackboard;
        if (drone_ == nullptr) return "ERROR";

        // Lógica do estado, executada a 20 Hz.
        //
        // Leitura de um dado publicado por um no de visao:
        //   bool *detectado = blackboard.get<bool>("alvo_detectado");
        //   if (detectado && *detectado) return "ALVO_ENCONTRADO";

        return "CONCLUIDO";   // "" mantém no estado; nome de outcome transita
    }

    void on_exit(fsm::Blackboard &blackboard) override {
        (void)blackboard;
    }

private:
    std::shared_ptr<Drone> drone_{nullptr};
    Eigen::Vector3d start_{0.0, 0.0, 0.0};
};

#endif  // ${PKG^^}__STATES__EXAMPLE_STATE_HPP_
EOF
else

# --------------------------------------------- no de exemplo + arvore (BT)
cat > "$PKG/include/$PKG/nodes/example_node.hpp" <<EOF
#ifndef ${PKG^^}__NODES__EXAMPLE_NODE_HPP_
#define ${PKG^^}__NODES__EXAMPLE_NODE_HPP_

// No de exemplo -- copie este arquivo para criar os seus.
//
// ANTES DE ESCREVER UM NO, PERGUNTE SE PRECISA DELE.
//
// A maior parte do que uma missao faz ja existe: o stdbt registra Arming,
// Takeoff, TakeoffAgain, GoTo, PrecisionLanding, ReturnHome e LandAndDisarm,
// todos adaptados dos estados do stdstates que ja voaram. E boa parte das
// DECISOES cabe em BlackboardBool e BlackboardMenorQue, sem codigo nenhum.
//
// Escreva um no quando a missao tiver logica propria -- ver uma base, decidir
// se ela e nova, contar quantas faltam.
//
// AS TRES FORMAS DE NO, e qual usar:
//
//   BT::SyncActionNode      termina no mesmo tick. Para calculo, registro,
//                           escrever na blackboard.
//   BT::StatefulActionNode  ocupa varios ticks: onStart, onRunning, onHalted.
//                           E o que usar para qualquer coisa que envolva
//                           mover o drone.
//   BT::ConditionNode       so responde sim ou nao, sem efeito colateral.
//
// Este exemplo e um StatefulActionNode, que e o caso mais comum e o unico com
// armadilha: o onHalted PRECISA existir e desfazer o que o no comecou. A
// arvore pode interromper um no a qualquer momento -- um decorador de timeout,
// um ReactiveFallback cuja condicao mudou -- e um no interrompido no meio de um
// deslocamento deixaria o drone se movendo.

#include <memory>
#include <string>

#include <behaviortree_cpp/action_node.h>

#include "drone/Drone.hpp"
#include "fsm/fsm.hpp"
#include "stdbt/fsm_action_node.hpp"   // kFsmBlackboardKey

class ExampleNode : public BT::StatefulActionNode
{
public:
    ExampleNode(const std::string &nome, const BT::NodeConfig &config)
        : BT::StatefulActionNode(nome, config) {}

    /// Portas sao a interface do no com o XML. Sem declarar, nao da para usar.
    ///
    ///     <ExampleNode voltas="5"/>
    static BT::PortsList providedPorts()
    {
        return {BT::InputPort<int>("voltas", 5, "quantos ciclos ficar RUNNING")};
    }

    BT::NodeStatus onStart() override
    {
        // A blackboard da FSM traz o drone e os parametros do YAML. E a mesma
        // que os nos do stdbt usam, entao este no e os adaptados enxergam
        // exatamente o mesmo estado.
        if (auto bb = config().blackboard) {
            bb->get<fsm::Blackboard *>(stdbt::kFsmBlackboardKey, fsm_bb_);
        }
        if (fsm_bb_ == nullptr) {
            return BT::NodeStatus::FAILURE;
        }

        auto *drone_ptr = fsm_bb_->get<std::shared_ptr<Drone>>("drone");
        if (drone_ptr == nullptr) return BT::NodeStatus::FAILURE;
        drone_ = *drone_ptr;

        getInput("voltas", restantes_);
        drone_->log("");
        drone_->log("NO: ExampleNode");
        return BT::NodeStatus::RUNNING;
    }

    BT::NodeStatus onRunning() override
    {
        if (--restantes_ > 0) {
            return BT::NodeStatus::RUNNING;
        }
        drone_->log("ExampleNode terminou.");
        return BT::NodeStatus::SUCCESS;
    }

    void onHalted() override
    {
        // Desfaca aqui o que o no comecou. Num no que move o drone, isto e
        // zerar a velocidade -- sem isso ele continua se movendo depois de
        // interrompido.
        if (drone_ != nullptr) {
            drone_->setLocalVelocity(0.0, 0.0, 0.0, 0.0);
        }
    }

private:
    std::shared_ptr<Drone> drone_;
    fsm::Blackboard *fsm_bb_ = nullptr;
    int restantes_ = 0;
};

#endif  // ${PKG^^}__NODES__EXAMPLE_NODE_HPP_
EOF

# ------------------------------------------------------------------- arvore
cat > "$PKG/trees/$PKG.xml" <<EOF
<?xml version="1.0"?>
<!--
  Arvore da missao $PKG.

  Este arquivo e INSTALADO no share/$PKG/trees/ e carregado em tempo de
  execucao. Editar aqui e relancar muda a missao SEM RECOMPILAR -- e e o que
  permite abrir a arvore no Groot2 e edita-la visualmente.

  Qual arvore carregar e parametro (tree_file), entao simulacao e voo podem
  usar arvores diferentes.

  ATENCAO: nome de no errado aqui NAO e erro de compilacao. Ele aparece so ao
  carregar. O test/test_tree.cpp existe exatamente para pegar isso no CI.

  Nos disponiveis sem escrever codigo (do stdbt):

    <Arming/>              arma
    <Takeoff/>             decola E reancora o referencial do mundo
    <TakeoffAgain/>        decola SEM reancorar (use na redecolagem)
    <GoTo/>                vai ate target_x/y/z/yaw da blackboard
    <PrecisionLanding/>    descida exponencial
    <ReturnHome/>          volta para casa em duas fases
    <LandAndDisarm/>       pousa e desarma

    <BlackboardBool chave="..."/>
    <BlackboardMenorQue chave="..." limite="..."/>

  E os compositores da propria BT: Sequence, Fallback, Parallel, Retry,
  Timeout, Inverter. Veja https://www.behaviortree.dev
-->
<root BTCPP_format="4">
  <BehaviorTree ID="Principal">
    <Sequence>
      <Arming/>
      <Takeoff/>
      <PrecisionLanding/>
    </Sequence>
  </BehaviorTree>
</root>
EOF

# --------------------------------------------------------- teste da arvore
cat > "$PKG/test/test_tree.cpp" <<EOF
// Teste da arvore.
//
// POR QUE ELE E OBRIGATORIO NUMA MISSAO EM BT
//
// Um nome de no errado no XML NAO e erro de compilacao. \`<Takeof/>\` em vez de
// \`<Takeoff/>\` compila, instala, e so falha quando a missao tenta carregar a
// arvore -- no chao, se voce tiver sorte; no ar, se nao tiver.
//
// Este teste carrega o XML INSTALADO com a mesma fabrica que a missao usa. Se
// um no nao existir, ou uma porta obrigatoria faltar, ele reprova no CI.
//
// E o preco de a arvore ser um arquivo editavel em vez de codigo, e vale a
// pena: em troca, mudar a logica da missao nao exige recompilar.

#include <string>

#include <gtest/gtest.h>

#include <ament_index_cpp/get_package_share_directory.hpp>
#include <behaviortree_cpp/bt_factory.h>

#include "stdbt/registrar.hpp"

// ACRESCENTE aqui os includes dos nos desta missao, e registre-os abaixo.
// #include "$PKG/nodes/meu_no.hpp"

namespace
{
BT::BehaviorTreeFactory fabricaDaMissao()
{
    BT::BehaviorTreeFactory factory;
    stdbt::registerAll(factory);
    // ACRESCENTE: factory.registerNodeType<MeuNo>("MeuNo");
    return factory;
}
}  // namespace

TEST(Arvore, TodosOsNosDoXmlEstaoRegistrados)
{
    auto factory = fabricaDaMissao();
    const auto caminho =
        ament_index_cpp::get_package_share_directory("$PKG") + "/trees/$PKG.xml";

    EXPECT_NO_THROW({
        auto arvore = factory.createTreeFromFile(caminho);
        (void)arvore;
    }) << "a arvore em " << caminho << " usa algum no que nao foi registrado";
}

TEST(Arvore, ONomeErradoRealmenteFalha)
{
    // O contraponto: confirma que o teste acima tem poder de fogo. Se esta
    // arvore obviamente errada passasse, o teste de cima nao provaria nada.
    auto factory = fabricaDaMissao();
    static const char *kXml = R"(
      <root BTCPP_format="4">
        <BehaviorTree ID="Principal">
          <NoQueNaoExiste/>
        </BehaviorTree>
      </root>)";

    EXPECT_ANY_THROW({
        auto arvore = factory.createTreeFromText(kXml);
        (void)arvore;
    });
}
EOF
fi

# ----------------------------------------------------------------- configs
for variant in simulation flight; do
cat > "$PKG/config/$variant.yaml" <<EOF
# Parametros da missao $PKG — perfil: $variant
#
# Estes valores sobrescrevem os padroes do codigo. Trocar de simulacao para
# voo real deve ser trocar de arquivo aqui, nunca editar o .cpp.
${PKG}_node:
  ros__parameters:
    # Decolagem (NED: altura negativa e para cima)
    takeoff_height: -2.5
    max_vertical_velocity: 1.2
    position_tolerance: 0.15

    # Pouso
    landing_velocity_max: 0.5
    landing_velocity_min: 0.15
    max_base_height: 0.5
    landing_timeout: 5.0

    # Movimento horizontal
    max_horizontal_velocity: 1.5

# O system_health do drone_lib tambem le deste arquivo.
system_health:
  ros__parameters:
    publish_rate: 1.0
EOF
done

# ----------------------------------------------------------------- launches
cat > "$PKG/launch/simulation.launch.py" <<EOF
#!/usr/bin/env python3
"""Launch de SIMULACAO da missao $PKG ($COMP)."""

import datetime
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, ExecuteProcess, TimerAction
from launch_ros.actions import Node


def generate_launch_description():
    params = os.path.join(get_package_share_directory('$PKG'), 'config', 'simulation.yaml')

    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    bag_dir = os.path.expanduser(f'~/evtol/mission_logs/${PKG}_{stamp}')

    # Grava um rosbag de cada voo. Depois de uma missao que deu errado, esta e
    # a unica forma de saber o que o drone via no momento.
    bag = ExecuteProcess(
        cmd=['ros2', 'bag', 'record', '-o', bag_dir,
             '/rosout',
             '/drone_trajectory',
             '/telemetry/drone_status',
             '/fmu/out/vehicle_local_position',
             '/fmu/out/vehicle_status',
             '/fmu/in/trajectory_setpoint'],
        output='screen')

    system_health = Node(
        package='drone_lib', executable='system_health',
        parameters=[params], output='screen')

    mission = Node(
        package='$PKG', executable='$PKG',
        parameters=[params], output='screen')

    # ACRESCENTE aqui os nos de visao desta missao, ex.:
    # vision = Node(package='cv_nodes_algum', executable='detector', output='screen')

    return LaunchDescription([
        DeclareLaunchArgument('rviz', default_value='false',
                              description='Abrir o RViz2'),
        bag,
        system_health,
        # A FSM espera 5 s para os outros nos subirem antes de comecar.
        TimerAction(period=5.0, actions=[mission]),
    ])
EOF

sed -e 's/simulation\.yaml/flight.yaml/' \
    -e 's/Launch de SIMULACAO/Launch de VOO REAL/' \
    "$PKG/launch/simulation.launch.py" > "$PKG/launch/flight.launch.py"

chmod +x "$PKG/launch/"*.py

# ---------------------------------------------------------------------------
# Atualiza as listas suspensas das tasks do VS Code, para que a missao recem
# criada ja apareca em "Tasks: Run Task" sem ninguem editar nada a mao.
#
# O VS Code so aceita lista fixa nos inputs; o sincronizador deriva a lista do
# que existe em src/. Sem isto, a task continuaria oferecendo so as missoes
# antigas -- que era exatamente o problema antes.
# ---------------------------------------------------------------------------
WS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$WS_ROOT/scripts/sync_tasks.py" ]]; then
    python3 "$WS_ROOT/scripts/sync_tasks.py" >/dev/null 2>&1 \
        && echo "Tasks do VS Code atualizadas: '$PKG' ja aparece em Tasks: Run Task." \
        || echo "AVISO: nao consegui atualizar as tasks do VS Code (rode: python3 scripts/sync_tasks.py)" >&2
fi

if [[ "$ENGINE" == "bt" ]]; then
cat <<EOF

Pacote '$PKG' criado em $PWD/$PKG   (motor: Behavior Tree)

  package.xml / CMakeLists.txt      dependencias e alvo prontos
  src/$PKG.cpp                      carrega a arvore, registra os nos, tick 20 Hz
  trees/$PKG.xml                    A ARVORE: Arming -> Takeoff -> PrecisionLanding
  include/$PKG/nodes/               seus nos (com example_node.hpp de modelo)
  test/test_tree.cpp                confere que todo no do XML existe
  config/{simulation,flight}.yaml   parametros
  launch/{simulation,flight}.launch.py

Ele ja compila e voa (arma, sobe, pousa). Proximos passos:

  1. cd ~/evtol/dev && bash src/$COMP/scripts/build.sh $PKG
  2. num terminal NOVO:
       source scripts/ros_env.sh && ros2 run $PKG $PKG
  3. mude a missao EDITANDO trees/$PKG.xml -- nao precisa recompilar.
     Os nos do stdbt ja disponiveis estao listados no comentario do XML.
  4. so escreva um no quando a missao tiver logica propria: copie
       $PKG/include/$PKG/nodes/example_node.hpp
     e registre-o nos blocos ACRESCENTE de src/$PKG.cpp E de test/test_tree.cpp

  Para ver a arvore ao vivo, abra o Groot2 e conecte na porta 1667.

EOF
else
cat <<EOF

Pacote '$PKG' criado em $PWD/$PKG   (motor: FSM)

  package.xml / CMakeLists.txt      dependencias e alvo prontos
  src/$PKG.cpp                      FSM + Node: ARMING -> TAKEOFF -> LANDING
  include/$PKG/states/              seus estados (com example_state.hpp de modelo)
  config/{simulation,flight}.yaml   parametros
  launch/{simulation,flight}.launch.py

Ele ja compila e voa (arma, sobe, pousa). Proximos passos:

  1. cd ~/evtol/dev && bash src/$COMP/scripts/build.sh $PKG
  2. num terminal NOVO:
       source scripts/ros_env.sh && ros2 run $PKG $PKG
  3. acrescente seus estados: copie
       $PKG/include/$PKG/states/example_state.hpp
     e ligue-o nos blocos marcados com ACRESCENTE em src/$PKG.cpp

EOF
fi
