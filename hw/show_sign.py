"""Mâna arată un semn.

Rulare pe Pi:
  python3 hw/show_sign.py 3           -> arată semnul 3
  python3 hw/show_sign.py 0 1 2 3 4 5 -> le arată pe rând
"""
import sys
import time

from poses import POSES
from robot_hand import release, set_fingers

HOLD = 2  # secunde cât ține fiecare semn


def main():
    signs = sys.argv[1:] or list(POSES)
    unknown = [s for s in signs if s not in POSES]
    if unknown:
        sys.exit(f"Semn necunoscut: {unknown}. Opțiuni: {list(POSES)}")

    try:
        for sign in signs:
            print(f"Semnul {sign}")
            set_fingers(POSES[sign])
            time.sleep(HOLD)
        set_fingers(POSES["5"])   # înapoi la mâna deschisă
    finally:
        release()


if __name__ == "__main__":
    main()
