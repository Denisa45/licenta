"""
Record hand landmarks from the webcam into data/landmarks.csv, in the same
format your pipeline already uses: label, take, x0, y0, z0, ... x20, y20, z20.

Every time you press 'r' to start recording, a NEW take id is created
(the current Unix time), so check_takes.py / clean_data.py / train_*.py
can treat each recording as one take.

Keys (click the camera window first):
    1-5 , L   choose which sign you are recording
    r     start / stop a take
    q     quit

Run from the ml folder, in the recording environment:
    .venv-record\\Scripts\\activate
    python record_takes.py
"""
import csv
import time
from collections import Counter, defaultdict
from pathlib import Path

import cv2
import mediapipe as mp

ML_DIR = Path(__file__).resolve().parent
DATA_DIR = ML_DIR / "data"
OUT_CSV = DATA_DIR / "landmarks.csv"
LABELS = "12345L"
SAVE_EVERY = 3  # save every 3rd frame (consecutive frames are near-identical)
HEADER = ["label", "take"] + [f"{a}{i}" for i in range(21) for a in "xyz"]


def normalize(landmarks):
    """Wrist at the origin, scaled so wrist -> middle-finger base = 1.
    This matches the existing data/landmarks.csv (checked with check_norm.py)."""
    pts = [(p.x, p.y, p.z) for p in landmarks]
    wx, wy, wz = pts[0]
    pts = [(x - wx, y - wy, z - wz) for x, y, z in pts]
    mx, my, mz = pts[9]
    scale = (mx ** 2 + my ** 2 + mz ** 2) ** 0.5 or 1.0
    flat = []
    for x, y, z in pts:
        flat += [x / scale, y / scale, z / scale]
    return flat


def load_existing():
    rows, takes = Counter(), defaultdict(set)
    last_take = 0
    if not OUT_CSV.exists():
        return rows, takes, last_take
    with open(OUT_CSV, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header != HEADER:
            raise SystemExit(
                "data/landmarks.csv has a different header than expected, "
                "so I will not write into it. Send me its first line."
            )
        for row in reader:
            if row:
                rows[row[0]] += 1
                takes[row[0]].add(row[1])
                last_take = max(last_take, int(row[1]))
    return rows, takes, last_take


def main():
    DATA_DIR.mkdir(exist_ok=True)
    rows, takes, last_take = load_existing()
    is_new = not OUT_CSV.exists()

    f = open(OUT_CSV, "a", newline="")
    writer = csv.writer(f)
    if is_new:
        writer.writerow(HEADER)

    hands = mp.solutions.hands.Hands(
        static_image_mode=False,
        max_num_hands=1,
        min_detection_confidence=0.6,
        min_tracking_confidence=0.5,
    )
    drawing = mp.solutions.drawing_utils

    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise SystemExit("Could not open the webcam.")

    label = "1"
    recording = False
    take = 0
    frame_idx = 0

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            res = hands.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))

            if res.multi_hand_landmarks:
                lm = res.multi_hand_landmarks[0]
                drawing.draw_landmarks(frame, lm, mp.solutions.hands.HAND_CONNECTIONS)
                if recording:
                    frame_idx += 1
                    if frame_idx % SAVE_EVERY == 0:
                        row = normalize(lm.landmark)
                        writer.writerow([label, take] + [round(v, 6) for v in row])
                        rows[label] += 1

            status = "REC" if recording else "paused"
            color = (0, 0, 255) if recording else (0, 200, 0)
            cv2.putText(frame, f"sign {label}  [{status}]", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
            summary = "  ".join(f"{l}:{rows[l]}r/{len(takes[l])}t" for l in LABELS)
            cv2.putText(frame, summary, (10, 62),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
            cv2.imshow("record takes", frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if key == ord("r"):
                recording = not recording
                if recording:
                    take = max(int(time.time()), last_take + 1)
                    last_take = take
                    frame_idx = 0
                    takes[label].add(str(take))
                else:
                    f.flush()
            elif key != 255 and chr(key).upper() in LABELS:
                label = chr(key).upper()
                recording = False  # switching sign ends the current take
                f.flush()
    finally:
        f.close()
        cap.release()
        cv2.destroyAllWindows()

    print("rows / takes per sign:",
          {l: (rows[l], len(takes[l])) for l in LABELS})
    print(f"Saved to {OUT_CSV}")


if __name__ == "__main__":
    main()
