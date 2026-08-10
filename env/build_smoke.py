#!/usr/bin/env python3
"""Testa de verdade se esta máquina consegue instalar um pacote `ament_python`.

Por que isso existe
-------------------
O `colcon build --symlink-install` instala pacotes `ament_python` chamando
`setup.py develop --editable`. Esse caminho depende de uma combinação de
`setuptools` e `packaging` que **nenhuma checagem de versão isolada consegue
expressar**, porque a restrição é uma RELAÇÃO entre os dois:

    setuptools <= 70.x   funciona com o packaging 21.3 do Ubuntu 22.04
    setuptools 71 a 79   exige packaging >= 23
    setuptools >= 80     nao funciona de jeito nenhum (removeu --editable)

Isso já quebrou o time de forma exemplar: uma máquina passou nas 36 checagens
do `doctor.sh` e falhou no primeiro pacote do build, porque tinha o setuptools
pinado correto e o `packaging` 21.3 do apt. A máquina de quem escreveu o pin
tinha um `packaging` novo instalado por acaso, e por isso o problema não
apareceu lá.

A lição: quando o que importa é um comportamento, teste o comportamento.

Este script cria um pacote `ament_python` mínimo num diretório temporário e
roda nele exatamente a invocação que o colcon faz. Não instala nada, não toca
no workspace, e some ao terminar. Leva menos de um segundo.

Uso
---
    python3 env/build_smoke.py

Sai 0 se o caminho funciona, 1 se não.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SETUP_PY = """\
from setuptools import setup

setup(
    name="evtol_build_smoke",
    version="0.0.0",
    packages=["evtol_build_smoke"],
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/evtol_build_smoke"]),
        ("share/evtol_build_smoke", ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="eVTOL ITA",
    maintainer_email="evtol@ita.br",
    description="pacote descartavel usado pelo doctor",
    license="MIT",
)
"""

PACKAGE_XML = """\
<?xml version="1.0"?>
<package format="3">
  <name>evtol_build_smoke</name>
  <version>0.0.0</version>
  <description>pacote descartavel usado pelo doctor</description>
  <maintainer email="evtol@ita.br">eVTOL ITA</maintainer>
  <license>MIT</license>
  <export><build_type>ament_python</build_type></export>
</package>
"""


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="evtol_smoke_") as tmp:
        root = Path(tmp) / "pkg"
        (root / "evtol_build_smoke").mkdir(parents=True)
        (root / "resource").mkdir()

        (root / "setup.py").write_text(SETUP_PY, encoding="utf-8")
        (root / "package.xml").write_text(PACKAGE_XML, encoding="utf-8")
        (root / "evtol_build_smoke" / "__init__.py").write_text("", encoding="utf-8")
        (root / "resource" / "evtol_build_smoke").write_text("", encoding="utf-8")

        build_dir = Path(tmp) / "build"
        build_dir.mkdir()

        # Exatamente o que o colcon faz num pacote ament_python com
        # --symlink-install.
        proc = subprocess.run(
            [
                sys.executable,
                "setup.py",
                "develop",
                "--editable",
                "--build-directory",
                str(build_dir),
                "--no-deps",
            ],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=120,
        )

    if proc.returncode == 0:
        print("Instalacao de pacote ament_python: OK")
        return 0

    out = (proc.stdout + proc.stderr).strip()
    print("FALHA ao instalar um pacote ament_python mínimo.", file=sys.stderr)
    print(file=sys.stderr)

    # Traduz as duas causas conhecidas para algo acionável.
    if "strip_trailing_zero" in out:
        print(
            "Causa: o `setuptools` instalado chama uma funcao do `packaging` que\n"
            "so existe a partir do packaging 23. O Ubuntu 22.04 traz o 21.3 via\n"
            "apt.\n\n"
            "  Corrija com:  pip install --user 'packaging>=23'\n"
            "  (ou baixe o setuptools para <71, que funciona com o 21.3)",
            file=sys.stderr,
        )
    elif "--editable" in out and "not recognized" in out:
        print(
            "Causa: o `setuptools` >= 80 removeu a opcao `--editable`, que o\n"
            "`colcon build --symlink-install` usa.\n\n"
            "  Corrija com:  pip install --user 'setuptools<80'",
            file=sys.stderr,
        )
    else:
        print("Saida do comando:", file=sys.stderr)
        for line in out.splitlines()[-15:]:
            print(f"  {line}", file=sys.stderr)

    print(file=sys.stderr)
    print(
        "Sem isto, `colcon build` falha no PRIMEIRO pacote Python e nao processa\n"
        "nenhum outro.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
