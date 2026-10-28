"""Test de flexie pentru degetele mâinii robotice.

Rulare pe Pi:
  python3 hw/test_fingers.py            -> fiecare deget pe rând
  python3 hw/test_fingers.py mijlociu   -> doar degetele numite
  python3 hw/test_fingers.py toate      -> toate odată
"""
import sys
import time

from robot_hand import FINGERS, LIMITS, move, release

CYCLES = 2


def main():
    args = sys.argv[1:]
    if args == ["toate"]:
        groups = [list(FINGERS)]
    else:
        names = args or list(FINGERS)
        unknown = [n for n in names if n not in FINGERS]
        if unknown:
            sys.exit(f"Deget necunoscut: {unknown}. Opțiuni: {list(FINGERS)} sau toate")
        groups = [[n] for n in names]

    try:
        for names in groups:
            for i in range(CYCLES):
                print(f"{names} ciclul {i + 1}: "
                      + ", ".join(f"{n} {LIMITS[n][0]} -> {LIMITS[n][1]}" for n in names))
                move({FINGERS[n]: LIMITS[n][1] for n in names})
                time.sleep(0.5)
                move({FINGERS[n]: LIMITS[n][0] for n in names})
                time.sleep(0.5)
    finally:
        release()
        print("Test terminat!")


if __name__ == "__main__":
    main()
