"""Test de flexie pentru degetele mâinii robotice.

Rulare pe Pi:
  python3 hw/test_fingers.py            -> fiecare deget pe rând
  python3 hw/test_fingers.py mijlociu   -> doar degetele numite
  python3 hw/test_fingers.py toate      -> toate odată
"""
import sys
import time

from robot_hand import CLOSED, FINGERS, OPEN, move, release

CYCLES = 2


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
                move({ch: CLOSED for ch in channels})
                time.sleep(0.5)
                move({ch: OPEN for ch in channels})
                time.sleep(0.5)
    finally:
        release()
        print("Test terminat!")


if __name__ == "__main__":
    main()
