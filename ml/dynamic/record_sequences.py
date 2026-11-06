"""
Record dynamic (moving) signs from the webcam into ../data/dynamic/sequences.csv.

One press of SPACE = one sequence: a 3-2-1 countdown, then DURATION seconds
(2 s) are recorded. Do the whole sign inside that window, starting from the
rest position. Every frame where MediaPipe sees the hand is saved with its time.

Columns: label, session, seq, t, x0, y0, z0, ... x20, y20, z20
  session  the day of the recording, e.g. 20261106 (the train script holds out
           the last day of each sign, like the "take" of the static signs;
           restarting the script on the same day stays the same session)
  seq      one id per recorded sequence
  t        seconds since the start of the sequence
  x, y, z  landmarks in PIXELS of the frame (x * width, y * height, z * width),
           NOT normalized: seq_features.py does that, so the features can still
           be changed later without recording again.

Keys (click the camera window first):
    n / p   next / previous sign in SIGNS
    SPACE   record one sequence of the current sign
    x       reject the last sequence (written to rejected.txt, removed by the
            train script)
    q       quit

Aim for 30+ sequences per sign, in at least 2 sessions (different days,
light, clothes), with both hands if the sign allows it.

Run from the ml/dynamic folder, in the recording environment:
    ..\\.venv-record\\Scripts\\activate
    python record_sequences.py
"""
import csv
import time
from collections import Counter
from pathlib import Path

import cv2
import mediapipe as mp

from seq_features import DURATION

# The dynamic signs of the app, as shown on pesemne.ro (LSR video dictionary):
# https://pesemne.ro/wp-content/uploads/clips/<name>.mp4, e.g. la-revedere.mp4.
# All are done with one hand. The names are the labels the app checks
# (the 'shape' field in Firestore).
SIGNS = [
    "LA_REVEDERE",  # open hand, the 4 fingers close and open, thumb stays out
    "SALUT",        # open hand raised, waves from the wrist
    "MULTUMESC",    # flat hand touches the chin, then moves away
    "DA",           # index up, then a closed fist
    "NU",           # index up, swings left-right
    "BINE",         # index + middle up, the hand moves down
    "MAMA",         # flat hand touches the cheek
    "TATA",         # "OK" hand at the temple, then to the side
    "BUNIC",        # fist at the cheek, twists
    "CAND",         # only the thumb out, at the cheek
    "UNDE",         # thumb out, hand horizontal, index bends in, repeated
    "AN",           # thumb + index hold the chin
    "SAPTAMANA",    # index from the chin forward (towards the other person)
    "APA",          # "OK" hand moves towards yourself, repeated
    "VINO",         # index bends towards yourself ("come here")
]

OUT_DIR = Path(__file__).resolve().parent.parent / "data" / "dynamic"
OUT_CSV = OUT_DIR / "sequences.csv"
REJECTED = OUT_DIR / "rejected.txt"
HEADER = ["label", "session", "seq", "t"] + [f"{a}{i}" for i in range(21) for a in "xyz"]
COUNTDOWN = 3.0


def load_counts():
    counts = Counter()
    if OUT_CSV.exists():
        with open(OUT_CSV, newline="") as f:
            reader = csv.reader(f)
            if next(reader, None) != HEADER:
                raise SystemExit(f"{OUT_CSV} has a different header, I will not write into it.")
            seen = set()
            for row in reader:
                if row and row[2] not in seen:
                    seen.add(row[2])
                    counts[row[0]] += 1
    return counts


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    counts = load_counts()
    is_new = not OUT_CSV.exists()
    f = open(OUT_CSV, "a", newline="")
    writer = csv.writer(f)
    if is_new:
        writer.writerow(HEADER)

    hands = mp.solutions.hands.Hands(
        static_image_mode=False, max_num_hands=1,
        min_detection_confidence=0.6, min_tracking_confidence=0.5,
    )
    drawing = mp.solutions.drawing_utils
    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    if not cap.isOpened():
        raise SystemExit("Could not open the webcam.")

    session = int(time.strftime("%Y%m%d"))
    sign = 0
    state = "idle"          # idle -> countdown -> recording -> idle
    state_start = 0.0
    seq_id = None
    last_seq = None
    frames = []             # (t, [63 pixel values]) of the current sequence
    seen_frames = 0
    message = ""

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            now = time.time()
            h, w = frame.shape[:2]
            res = hands.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            lm = res.multi_hand_landmarks[0] if res.multi_hand_landmarks else None
            if lm is not None:
                drawing.draw_landmarks(frame, lm, mp.solutions.hands.HAND_CONNECTIONS)

            if state == "countdown" and now - state_start >= COUNTDOWN:
                state, state_start = "recording", now
                seq_id = int(now * 1000)
                frames, seen_frames = [], 0
            if state == "recording":
                seen_frames += 1
                t = now - state_start
                if lm is not None:
                    vals = []
                    for p in lm.landmark:
                        vals += [p.x * w, p.y * h, p.z * w]
                    frames.append((t, vals))
                if t >= DURATION:
                    state = "idle"
                    label = SIGNS[sign]
                    if len(frames) < 0.6 * seen_frames or len(frames) < 5:
                        message = f"hand seen in {len(frames)}/{seen_frames} frames: NOT saved, try again"
                    else:
                        for ft, vals in frames:
                            writer.writerow([label, session, seq_id, round(ft, 4)]
                                            + [round(v, 3) for v in vals])
                        f.flush()
                        counts[label] += 1
                        last_seq = seq_id
                        message = f"saved {label} #{counts[label]} ({len(frames)} frames)"

            label = SIGNS[sign]
            if state == "countdown":
                left = COUNTDOWN - (now - state_start)
                cv2.putText(frame, str(int(left) + 1), (w // 2 - 30, h // 2 + 30),
                            cv2.FONT_HERSHEY_SIMPLEX, 3, (0, 200, 255), 6)
            elif state == "recording":
                cv2.circle(frame, (w - 30, 30), 14, (0, 0, 255), -1)
                done = (now - state_start) / DURATION
                cv2.rectangle(frame, (0, h - 12), (int(w * min(done, 1)), h), (0, 0, 255), -1)
            cv2.putText(frame, f"sign {label} ({counts[label]} saved)  [n/p change, SPACE record]",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 0), 2)
            cv2.putText(frame, message, (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
            cv2.imshow("record dynamic signs", frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if state != "idle":
                continue
            if key == ord(" "):
                state, state_start, message = "countdown", now, ""
            elif key == ord("n"):
                sign = (sign + 1) % len(SIGNS)
            elif key == ord("p"):
                sign = (sign - 1) % len(SIGNS)
            elif key == ord("x") and last_seq is not None:
                with open(REJECTED, "a") as r:
                    r.write(f"{last_seq}\n")
                message = f"sequence {last_seq} rejected"
                last_seq = None
    finally:
        f.close()
        cap.release()
        cv2.destroyAllWindows()
    print("sequences per sign:", dict(counts))


if __name__ == "__main__":
    main()
