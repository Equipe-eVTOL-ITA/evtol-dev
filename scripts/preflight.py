#!/usr/bin/env python3
"""O miolo do pre-voo. Chamado por scripts/preflight.sh, que carrega o ROS.

Cada checagem responde a uma falha que nao imprime erro nenhum quando acontece.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

VERDE, VERMELHO, AMARELO, CINZA, FIM = (
    "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m")
if not sys.stdout.isatty():
    VERDE = VERMELHO = AMARELO = CINZA = FIM = ""

falhas: list[str] = []
avisos: list[str] = []


def ok(item: str, detalhe: str = "") -> None:
    print(f"  {VERDE}ok{FIM}   {item}" + (f"  {CINZA}{detalhe}{FIM}" if detalhe else ""))


def falha(item: str, conserto: str = "") -> None:
    print(f"  {VERMELHO}FALHA{FIM} {item}")
    if conserto:
        print(f"        -> {conserto}")
    falhas.append(item)


def aviso(item: str, nota: str = "") -> None:
    print(f"  {AMARELO}aviso{FIM} {item}" + (f"  {CINZA}{nota}{FIM}" if nota else ""))
    avisos.append(item)


def roda(cmd: list[str], timeout: float = 10.0) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


# --------------------------------------------------------------------------- #
# 1. O grafo esta de pe?
# --------------------------------------------------------------------------- #

def checar_grafo() -> list[str]:
    print("Grafo ROS")
    nos = [n for n in roda(["ros2", "node", "list"]).split() if n]
    if not nos:
        falha("nenhum no no grafo",
              "a missao esta rodando? ros2 node list deveria listar algo")
        return []
    ok(f"{len(nos)} no(s) no ar", ", ".join(sorted(nos)[:6]))
    return nos


# --------------------------------------------------------------------------- #
# 2. O PX4 esta falando?
# --------------------------------------------------------------------------- #

def checar_px4() -> None:
    print("\nLigacao com o PX4")
    topicos = roda(["ros2", "topic", "list"]).split()
    if "/fmu/out/vehicle_status" not in topicos:
        falha("/fmu/out/vehicle_status nao existe",
              "o agente esta rodando? ./scripts/agent.sh  (ou --serial, em voo)")
        return

    # Nao basta o topico existir: um agente vivo com o cabo solto produz
    # exatamente isso. Com `timeout` do shell -- o `ros2 topic echo` do Humble
    # nao tem `--timeout`, e passa-la faria o checador acusar falha por erro
    # proprio.
    saida = roda(["timeout", "6", "ros2", "topic", "echo", "--once",
                  "/fmu/out/vehicle_status"], timeout=10)
    if saida.strip():
        ok("/fmu/out/vehicle_status esta chegando")
    else:
        falha("/fmu/out/vehicle_status existe mas nao chega mensagem",
              "agente de pe e PX4 mudo: confira o cabo/porta, ou o udp4 -p 8888")


# --------------------------------------------------------------------------- #
# 3. QoS e publicadores  --  as duas falhas mais caras do repositorio
# --------------------------------------------------------------------------- #

RELIABILITY = re.compile(r"Reliability:\s*(\w+)")


def qos_por_papel(info: str) -> tuple[list[str], list[str]]:
    """(reliability dos publicadores, dos assinantes) de `topic info -v`.

    O formato nao tem cabecalhos "Publishers:"/"Subscriptions:": e um bloco por
    endpoint, cada um com a sua linha `Endpoint type:` e o seu `QoS profile`.
    """
    pubs: list[str] = []
    subs: list[str] = []
    papel: str | None = None

    for linha in info.splitlines():
        s = linha.strip()
        if s.startswith("Endpoint type:"):
            papel = s.split(":", 1)[1].strip()
            continue
        m = RELIABILITY.match(s)
        if m and papel:
            (pubs if papel == "PUBLISHER" else subs).append(m.group(1))
            papel = None
    return pubs, subs


# Sem publicador AQUI a missao voa cega, e nenhum erro e impresso.
CRITICOS = {
    "/fmu/out/vehicle_status",
    "/fmu/out/vehicle_odometry",
    "/fmu/in/trajectory_setpoint",
    "/fmu/in/offboard_control_mode",
    "/fmu/in/vehicle_command",
}


def e_critico(topico: str) -> bool:
    return (topico in CRITICOS
            or "camera" in topico
            or "image" in topico
            or topico.endswith(("/detections", "/gestures", "/scan")))


def checar_topicos_assinados(nos: list[str]) -> None:
    print("\nTopicos que a missao assina")

    assinados: dict[str, set[str]] = {}
    for no in nos:
        info = roda(["ros2", "node", "info", no])
        secao = None
        for linha in info.splitlines():
            s = linha.strip()
            if s.startswith("Subscribers:"):
                secao = "sub"
                continue
            if s.endswith(":") and not s.startswith("/"):
                secao = None
                continue
            if secao == "sub" and s.startswith("/"):
                nome = s.split(":")[0].strip()
                assinados.setdefault(nome, set()).add(no)

    if not assinados:
        aviso("nenhuma assinatura encontrada", "ros2 node info nao respondeu?")
        return

    for topico in sorted(assinados):
        if topico in ("/parameter_events", "/rosout", "/clock"):
            continue

        info = roda(["ros2", "topic", "info", "-v", topico])
        if not info.strip():
            falha(f"{topico}: nao consegui inspecionar")
            continue

        qos_pub, qos_sub = qos_por_papel(info)

        if not qos_pub:
            # A severidade depende do topico: o sim2d nao simula airspeed nem
            # bateria, e um checador que sempre reprova nao e lido.
            if e_critico(topico):
                falha(f"{topico}: NENHUM publicador",
                      "quem deveria publicar isto subiu? confira o nome do "
                      "topico contra a convencao (docs/CONTRATOS.md, "
                      "topicos.camera)")
            else:
                aviso(f"{topico}: nenhum publicador",
                      "normal num simulador reduzido; em voo, nao")
            continue

        # Publicador BEST_EFFORT com assinante RELIABLE nao se falam, e nada
        # e impresso: o topico aparece, o info mostra o publicador, e nenhuma
        # mensagem chega.
        if "BEST_EFFORT" in qos_pub and "RELIABLE" in qos_sub:
            falha(f"{topico}: QoS INCOMPATIVEL "
                  f"(pub={'/'.join(sorted(set(qos_pub)))}, "
                  f"sub={'/'.join(sorted(set(qos_sub)))})",
                  "publicador best-effort e assinante reliable nunca se falam; "
                  "nenhuma mensagem chega e nenhum erro e impresso")
        else:
            ok(f"{topico}", f"{len(qos_pub)} pub, QoS compativel")


# --------------------------------------------------------------------------- #
# 4. Taxas reais
# --------------------------------------------------------------------------- #

HZ = re.compile(r"average rate:\s*([\d.]+)")


def checar_taxas() -> None:
    print("\nTaxas medidas (3 s cada)")
    topicos = set(roda(["ros2", "topic", "list"]).split())

    # (topico, minimo aceitavel em Hz)
    alvos = [
        ("/telemetry/position", 10.0),
        ("/fmu/out/vehicle_odometry", 10.0),
    ]
    alvos += [(t, 3.0) for t in sorted(topicos)
              if t.endswith("_camera/compressed") or t.endswith("/detections")]

    for topico, minimo in alvos:
        if topico not in topicos:
            continue
        # 5 amostras em ate 6 s: com `-w 10` a 8 Hz a media nao fechava a
        # tempo, e topicos vivos apareciam como "sem trafego".
        saida = roda(["timeout", "6", "ros2", "topic", "hz", "-w", "5", topico],
                     timeout=9)
        m = HZ.search(saida)
        if not m:
            falha(f"{topico}: sem trafego", "o topico existe, mas nao passa nada")
            continue
        hz = float(m.group(1))
        if hz < minimo:
            aviso(f"{topico}: {hz:.1f} Hz", f"esperado >= {minimo:g} Hz")
        else:
            ok(f"{topico}", f"{hz:.1f} Hz")


# --------------------------------------------------------------------------- #
# 5. Parametros: placeholders e o que difere do arquivo
# --------------------------------------------------------------------------- #

def checar_parametros(config: Path, nos: list[str]) -> None:
    print("\nParametros")
    try:
        import yaml
        declarado = yaml.safe_load(config.read_text(encoding="utf-8")) or {}
    except Exception as e:
        falha(f"nao consegui ler {config}: {e}")
        return

    # 5a. Placeholders que precisam ser trocados antes de voar.
    for no, corpo in declarado.items():
        params = (corpo or {}).get("ros__parameters", {}) or {}
        for chave in ("camera_fx", "camera_fy", "camera_cx", "camera_cy"):
            if chave in params and float(params[chave] or 0) == 0.0:
                falha(f"{no}.{chave} = 0.0 (PLACEHOLDER)",
                      "rode o camera_calibrator com a camera que vai voar e "
                      "cole os valores; com 0 o codigo cai num pinhole nominal "
                      "de 60 graus e a posicao estimada fica errada em silencio")

    # 5b. O topico de imagem declarado existe de fato?
    vivos = set(roda(["ros2", "topic", "list"]).split())
    for no, corpo in declarado.items():
        params = (corpo or {}).get("ros__parameters", {}) or {}
        alvo = params.get("image_topic")
        if not alvo:
            continue
        if alvo in vivos:
            ok(f"{no}.image_topic", alvo)
        else:
            parecidos = [t for t in sorted(vivos) if "camera" in t][:4]
            falha(f"{no}.image_topic = '{alvo}' NAO EXISTE no grafo",
                  "o detector vai subir, nao reclamar e nunca receber quadro. "
                  + (f"Existem: {', '.join(parecidos)}" if parecidos
                     else "Nenhum topico de camera no ar."))

    # 5c. Um launch que sobe um no sem `name=` deixa o no com o nome padrao,
    # e a secao do YAML nao se aplica a ele: cai nos defaults, e o arquivo diz
    # uma coisa enquanto o sistema faz outra.
    nomes_no_yaml = {n.lstrip("/") for n in declarado}
    nomes_vivos = {n.lstrip("/") for n in nos}
    orfas = nomes_no_yaml - nomes_vivos - {"/**"}
    for secao in sorted(orfas):
        aviso(f"o YAML tem a secao '{secao}', e nao ha no com esse nome",
              "esses parametros nao estao valendo para ninguem")


# --------------------------------------------------------------------------- #

def main() -> int:
    if len(sys.argv) < 3:
        print("uso: preflight.py <pacote> <config.yaml>", file=sys.stderr)
        return 2
    config = Path(sys.argv[2])

    nos = checar_grafo()
    if nos:
        checar_px4()
        checar_topicos_assinados(nos)
        checar_taxas()
        checar_parametros(config, nos)

    print()
    if falhas:
        print(f"{VERMELHO}REPROVOU{FIM}: {len(falhas)} problema(s), "
              f"{len(avisos)} aviso(s).")
        print("\nNao arme antes de resolver:")
        for f in falhas:
            print(f"  - {f}")
        return 1

    print(f"{VERDE}Pronto para armar{FIM}"
          + (f" ({len(avisos)} aviso(s))" if avisos else "."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
