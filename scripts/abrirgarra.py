#!/usr/bin/env python

import RPi.GPIO as GPIO
import time

# Pin Mapping
output_pins = {
    'JETSON_XAVIER': 18,
    'JETSON_NANO': 33,
    'JETSON_NX': 33,
    'CLARA_AGX_XAVIER': 18,
    'JETSON_TX2_NX': 32,
    'JETSON_ORIN': 18,
    'JETSON_ORIN_NX': 33,
    'JETSON_ORIN_NANO': 33
}

output_pin = output_pins.get(GPIO.model, None)
if output_pin is None:
    raise Exception('PWM not supported on this board')

# --- Configuration Constants ---
DUTY_LOW = 2.5   # Corresponds to 0 (Closed)
DUTY_HIGH = 12.0  # Corresponds to 1 (Open)

def main():
    GPIO.setmode(GPIO.BOARD)
    GPIO.setup(output_pin, GPIO.OUT)
    
    # Initialize PWM at 50Hz
    p = GPIO.PWM(output_pin, 50)
    p.start(DUTY_LOW) # Start at closed position

    print("Servo Control Ready.")
    print("Enter 1 to Open, 0 to Close, or 'q' to Quit.")

    try:
        while True:

            p.ChangeDutyCycle(DUTY_LOW)
            
            # Give the servo time to move before the next command
            time.sleep(0.5)

    finally:
        p.stop()
        GPIO.cleanup()

if __name__ == '__main__':
    main()