"""
Extract MediaPipe hand landmarks from photos.

Expected layout (one folder per sign, folder name = label):
    LICENTA/pic/0/*.jpg
    LICENTA/pic/1/*.jpg
    ...
    LICENTA/pic/5/*.jpg

Output: LICENTA/ml/landmarks_from_photos.csv
    columns: label, x0, y0, z0, ... x20, y20, z20   (63 normalized values)

Run from the ml folder with your venv active:
    pip install mediapipe opencv-python
    python extract_landmarks.py
"""
import csv
from pathlib import Path

import cv2
import mediapipe as mp

ML_DIR = Path(__file__).resolve().parent
PIC_DIR = ML_DIR.parent / "pic"
OUT_CSV = ML_DIR / "landmarks_from_photos.csv"
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

# Also process a mirrored copy of every photo, so the model sees
# left and right hands even if you only photographed one.
USE_MIRROR = True


def normalize(landmarks):
    """Wrist-relative, scaled by hand size. Use the SAME function in the app."""
    pts = [(p.x, p.y, p.z) for p in landmarks]
    wx, wy, wz = pts[0]
    pts = [(x - wx, y - wy, z - wz) for x, y, z in pts]
    mx, my, mz = pts[9]  # middle finger base
    scale = (mx ** 2 + my ** 2 + mz ** 2) ** 0.5 or 1.0
    flat = []
    for x, y, z in pts:
        flat += [x / scale, y / scale, z / scale]
    return flat


def main():
    if not PIC_DIR.exists():
        raise SystemExit(f"Folder not found: {PIC_DIR}")

    hands = mp.solutions.hands.Hands(
        static_image_mode=True,
        max_num_hands=1,
        min_detection_confidence=0.5,
    )

    header = ["label"] + [f"{a}{i}" for i in range(21) for a in "xyz"]
    stats = {}

    with open(OUT_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)

        for label_dir in sorted(p for p in PIC_DIR.iterdir() if p.is_dir()):
            label = label_dir.name
            total = ok = 0
            for img_path in sorted(label_dir.iterdir()):
                if img_path.suffix.lower() not in EXTS:
                    continue
                img = cv2.imread(str(img_path))
                if img is None:
                    print(f"  could not read {img_path.name}")
                    continue
                total += 1
                variants = [img]
                if USE_MIRROR:
                    variants.append(cv2.flip(img, 1))
                found = False
                for v in variants:
                    rgb = cv2.cvtColor(v, cv2.COLOR_BGR2RGB)
                    res = hands.process(rgb)
                    if res.multi_hand_landmarks:
                        found = True
                        row = normalize(res.multi_hand_landmarks[0].landmark)
                        writer.writerow([label] + [round(v_, 6) for v_ in row])
                        ok += 1
                if not found:
                    print(f"  no hand detected: {label}/{img_path.name}")
            stats[label] = (total, ok)

    print("\nlabel | photos | rows written")
    for label, (total, ok) in stats.items():
        print(f"  {label}   | {total:5d}  | {ok}")
    print(f"\nSaved to {OUT_CSV}")


if __name__ == "__main__":
    main()
