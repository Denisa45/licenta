import csv
import os
import time

import cv2
import mediapipe as mp
import numpy as np

LABELS = ["1", "2", "3", "4", "5"]
OUT = "data/landmarks.csv"
os.makedirs("data", exist_ok=True)

mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils


def normalize(hand_landmarks):
    """63 numbers: wrist at the origin, scaled by wrist -> middle finger base."""
    pts = np.array([[lm.x, lm.y, lm.z] for lm in hand_landmarks.landmark],
                   dtype=np.float32)
    pts -= pts[0]
    scale = np.linalg.norm(pts[9])
    if scale > 1e-6:
        pts /= scale
    return pts.flatten()


def main():
    counts = {label: 0 for label in LABELS}
    file_new = not os.path.exists(OUT)
    if not file_new:
        with open(OUT) as f:
            for row in csv.reader(f):
                if row and row[0] in counts:
                    counts[row[0]] += 1

    f = open(OUT, "a", newline="")
    writer = csv.writer(f)
    if file_new:
        writer.writerow(["label", "take"] +
                        [f"{a}{i}" for i in range(21) for a in "xyz"])

    cap = cv2.VideoCapture(0)
    current = LABELS[0]
    recording = False
    take_id = 0
    frame_i = 0

    with mp_hands.Hands(max_num_hands=1,
                        min_detection_confidence=0.6,
                        min_tracking_confidence=0.6) as hands:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frame_i += 1

            result = hands.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            hand_seen = bool(result.multi_hand_landmarks)
            if hand_seen:
                hl = result.multi_hand_landmarks[0]
                mp_draw.draw_landmarks(frame, hl, mp_hands.HAND_CONNECTIONS)
                if recording and frame_i % 3 == 0:
                    writer.writerow([current, take_id] + normalize(hl).tolist())
                    counts[current] += 1

            view = cv2.flip(frame, 1)  # mirror, so it feels like a mirror
            status = "REC" if recording else "paused"
            color = (0, 0, 255) if recording else (0, 200, 0)
            cv2.putText(view, f"Sign {current} | {status} | hand: {hand_seen}",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)
            cv2.putText(view, "  ".join(f"{l}:{counts[l]}" for l in LABELS),
                        (10, 65), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
            cv2.putText(view, "1-5 = choose sign | SPACE = start/stop | q = quit",
                        (10, view.shape[0] - 15), cv2.FONT_HERSHEY_SIMPLEX,
                        0.55, (255, 255, 255), 1)
            cv2.imshow("Record landmarks", view)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            elif key == 32:
                recording = not recording
                if recording:
                    take_id = int(time.time())
            elif chr(key) in LABELS:
                current = chr(key)
                recording = False

    f.close()
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()