"""Test de flexie pentru degetele mâinii robotice.

Rulare pe Pi:
  python3 hw/test_fingers.py            -> fiecare deget pe rând
  python3 hw/test_fingers.py mijlociu   -> doar degetele numite
  python3 hw/test_fingers.py toate      -> toate odată
"""
import sys
import time

from adafruit_servokit import ServoKit

# deget -> canal pe PCA9685
FINGERS = {"police": 0, "aratator": 1, "mijlociu": 2, "inelar": 4, "mic": 5}
OPEN, CLOSED = 150, 0     # 150 = deget întins, 0 = deget îndoit
CYCLES = 2

kit = ServoKit(channels=16)
for ch in FINGERS.values():
    kit.servo[ch].set_pulse_width_range(600, 2400)


def move(channels, target, step=5, delay=0.02):
    """Mută gradual toate canalele date spre același unghi."""
    start = {}
    for ch in channels:
        angle = kit.servo[ch].angle
        start[ch] = OPEN if angle is None else angle
    n = max(1, int(max(abs(target - a) for a in start.values()) / step))
    for k in range(1, n + 1):
        for ch, a in start.items():
            kit.servo[ch].angle = a + (target - a) * k / n
        time.sleep(delay)


def main():
    args = sys.argv[1:]
    if args == ["toate"]:
        groups = [list(FINGERS.values())]
    else:
        names = args or list(FINGERS)
        unknown = [n for n in names if n not in FINGERS]
        if unknown:
            sys.exit(f"Deget necunoscut: {unknown}. Opțiuni: {list(FINGERS)} sau toate")
        groups = [[FINGERS[n]] for n in names]

    try:
        for channels in groups:
            for i in range(CYCLES):
                print(f"CH{channels} ciclul {i + 1}: {OPEN} -> {CLOSED} -> {OPEN}")
                move(channels, CLOSED)
                time.sleep(0.5)
                move(channels, OPEN)
                time.sleep(0.5)
    finally:
        for ch in FINGERS.values():
            kit.servo[ch].angle = None   # oprește semnalul, servo liber
        print("Test terminat!")


if __name__ == "__main__":
    main()
