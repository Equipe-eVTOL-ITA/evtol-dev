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
Uso: new_mission.sh <nome_da_missao>

  Rode de dentro do repositório da competição, ex.:

      cd ~/evtol/dev/src/cbr2027
      ~/evtol/dev/templates/new_mission.sh fase1

  O nome deve ser um identificador válido de pacote ROS: minúsculas,
  dígitos e underscore, começando por letra. Ex.: fase1, missao_2, fase_final
EOF
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
case "${1}" in -h|--help) usage; exit 0 ;; esac

PKG="$1"
[[ "$PKG" =~ ^[a-z][a-z0-9_]*$ ]] || \
    die "'$PKG' não é um nome válido de pacote ROS (minúsculas, dígitos, underscore, começando por letra)."

[[ -d .git ]] || echo "AVISO: você não parece estar na raiz de um repositório git." >&2
[[ -e "$PKG" ]] && die "'$PKG' já existe aqui. Escolha outro nome ou apague o diretório."

# fase1 -> Fase1 ; missao_2 -> Missao2   (para os nomes de classe)
CLASS="$(echo "$PKG" | awk -F_ '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')"

# Identificação do maintainer. O catkin_pkg REJEITA e-mail inválido, e o erro
# de parse resultante não explica a causa -- por isso pegamos do git.
MAINT_NAME="$(git config user.name  2>/dev/null || true)"; MAINT_NAME="${MAINT_NAME:-eVTOL ITA}"
MAINT_MAIL="$(git config user.email 2>/dev/null || true)"; MAINT_MAIL="${MAINT_MAIL:-evtol@ita.br}"
[[ "$MAINT_MAIL" == *@*.* ]] || die "e-mail do git ('$MAINT_MAIL') não é válido; ajuste com: git config user.email seu@email.com"

COMP="$(basename "$PWD")"

mkdir -p "$PKG"/{src,config,launch} "$PKG/include/$PKG/states"

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
  custom_msgs
  nav_msgs
  geometry_msgs
  std_msgs
)

install(TARGETS $PKG DESTINATION lib/\${PROJECT_NAME})
install(DIRECTORY launch/ DESTINATION share/\${PROJECT_NAME}/launch)
install(DIRECTORY config/ DESTINATION share/\${PROJECT_NAME}/config)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()
endif()

ament_package()
EOF

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

cat <<EOF

Pacote '$PKG' criado em $PWD/$PKG

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
