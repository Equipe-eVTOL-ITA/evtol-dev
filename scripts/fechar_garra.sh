#!/bin/bash
# ==========================================================
# fechar_garra.sh — Aciona servo para fechar a garra
# ==========================================================
set -e

SERVO_SCRIPT="$HOME/jetson-gpio/samples/servoControl.py"

if [ ! -f "$SERVO_SCRIPT" ]; then
    echo "Error: Servo control script not found at $SERVO_SCRIPT"
    echo "Make sure the jetson-gpio package is installed."
    exit 1
fi

echo "Acionando servo — fechando garra..."
python3 "$SERVO_SCRIPT"
