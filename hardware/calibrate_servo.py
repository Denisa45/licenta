"""Calibrare interactivă a unui servo pe PCA9685.

Rulare pe Pi:  python3 calibrate_servo.py --channel 0
Taste: a/d = -/+ 10 µs, A/D = -/+ 50 µs, n = salvează MIN, x = salvează MAX, q = ieșire
"""
import argparse

import board
import busio
from adafruit_pca9685 import PCA9685

FREQ = 50
PERIOD_US = 1_000_000 / FREQ
PULSE_LIMITS = (500, 2500)  # MG996R; nu trece de aici


def set_pulse(channel, us):
    channel.duty_cycle = int(us / PERIOD_US * 0xFFFF)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel", type=int, default=0)
    parser.add_argument("--start", type=int, default=1500, help="puls inițial în µs")
    args = parser.parse_args()

    pca = PCA9685(busio.I2C(board.SCL, board.SDA))
    pca.frequency = FREQ
    ch = pca.channels[args.channel]

    us, saved = args.start, {}
    steps = {"a": -10, "d": 10, "A": -50, "D": 50}
    try:
        set_pulse(ch, us)
        while True:
            key = input(f"puls = {us} µs  [a/d/A/D, n=MIN, x=MAX, q] > ").strip()
            if key in steps:
                us = max(PULSE_LIMITS[0], min(PULSE_LIMITS[1], us + steps[key]))
                set_pulse(ch, us)
            elif key == "n":
                saved["MIN"] = us
            elif key == "x":
                saved["MAX"] = us
            elif key == "q":
                break
    finally:
        ch.duty_cycle = 0  # servo liber, fără cuplu
        pca.deinit()
        print(f"CH{args.channel}: {saved}")


if __name__ == "__main__":
    main()
