#!/usr/bin/env python3
"""
Abre a garra (servo PWM) via GPIO -- chamado por OpenGripperState
(fase4_itjbx/include/fase4_itjbx/states/open_gripper_state.hpp) atraves de
`std::system("python3 " + script_path)`, que BLOQUEIA a FSM ate' este
processo terminar. Por isso o script tem que fazer o movimento e sair --
nao pode ficar rodando (isso trava o offboard do PX4 em pleno voo).

Hardware: Raspberry Pi 5, servo no GPIO 12 (numeracao BCM; pino fisico 32
no conector de 40 pinos).

Raspberry Pi 5 usa um chip GPIO novo (RP1); o pacote RPi.GPIO classico
(PyPI, Ben Croston) e' conhecido por nao funcionar direito nela. Se o
servo nao se mexer, o suspeito numero um NAO e' este script -- e':

    sudo apt remove python3-rpi.gpio    # se instalado via pip/PyPI
    sudo apt install python3-rpi-lgpio  # drop-in: mesmo `import RPi.GPIO`,
                                         # implementado com lgpio por baixo
"""

import RPi.GPIO as GPIO
import time

GPIO_PIN = 12  # BCM -- pino fisico 32

# Duty cycle (%) em 50Hz -- faixa tipica de servo hobby (pulso ~0.5-2.5ms).
DUTY_CLOSED = 2.5
DUTY_OPEN = 12.0

# Tempo (s) segurando o duty de abertura antes de parar o PWM -- da' folga
# pro servo terminar o curso fisico antes do sinal sumir.
OPEN_HOLD_S = 1.0


def main() -> None:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(GPIO_PIN, GPIO.OUT)

    pwm = GPIO.PWM(GPIO_PIN, 50)
    pwm.start(DUTY_CLOSED)

    try:
        pwm.ChangeDutyCycle(DUTY_OPEN)
        time.sleep(OPEN_HOLD_S)
    finally:
        pwm.stop()
        GPIO.cleanup()


if __name__ == '__main__':
    main()
