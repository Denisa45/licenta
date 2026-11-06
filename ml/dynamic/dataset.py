"""
Loads ../data/dynamic/sequences.csv as one entry per recorded sequence, and
splits it the same way as the static signs: for every sign, the last recording
session is the held-out test set (if the sign has only one session, its last
20% sequences are used instead).

A session is the DAY a sequence was recorded (from its seq id, a timestamp),
not one run of record_sequences.py: restarting the script on the same day
keeps the same light and clothes, so those sequences must not end up split
between training and test.
"""
import os
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from seq_features import T, MIN_HAND_FRAMES, DURATION, features, resample

# DYNAMIC_DATA lets a test run use another folder.
DATA = Path(os.environ.get("DYNAMIC_DATA", Path(__file__).resolve().parent.parent / "data" / "dynamic"))
CSV = DATA / "sequences.csv"
REJECTED = DATA / "rejected.txt"
POINT_COLS = [f"{a}{i}" for i in range(21) for a in "xyz"]


@dataclass
class Sequence:
    label: str
    session: int
    seq: int
    times: np.ndarray   # (k,)
    points: np.ndarray  # (k, 21, 3) pixel units

    def feats(self):
        return features(resample(self.times, self.points, T))


def load(csv=CSV):
    df = pd.read_csv(csv, dtype={"label": str})
    rejected = set()
    if REJECTED.exists():
        rejected = {int(l) for l in REJECTED.read_text().split() if l.strip()}
    out = []
    for (label, seq), g in df.groupby(["label", "seq"], sort=False):
        if seq in rejected:
            continue
        g = g.sort_values("t")
        # The recorder already drops sequences where the hand was mostly
        # missing; this also catches sequences recorded by an older version.
        if len(g) < 5 or g["t"].iloc[-1] - g["t"].iloc[0] < MIN_HAND_FRAMES * DURATION:
            continue
        session = int(datetime.fromtimestamp(int(seq) / 1000).strftime("%Y%m%d"))
        out.append(Sequence(label, session, int(seq), g["t"].to_numpy(),
                            g[POINT_COLS].to_numpy(dtype=np.float64).reshape(-1, 21, 3)))
    return out


def split(seqs):
    train, test = [], []
    for label in sorted({s.label for s in seqs}):
        mine = sorted((s for s in seqs if s.label == label), key=lambda s: s.seq)
        sessions = sorted({s.session for s in mine})
        if len(sessions) >= 2:
            train += [s for s in mine if s.session != sessions[-1]]
            test += [s for s in mine if s.session == sessions[-1]]
        else:
            print(f"NOTE: sign {label} has one session only, holding out its last 20% sequences.")
            k = max(1, len(mine) // 5)
            train += mine[:-k]
            test += mine[-k:]
    return train, test


def summary(seqs):
    df = pd.DataFrame([(s.label, s.session) for s in seqs], columns=["label", "session"])
    return df.groupby("label").agg(sequences=("session", "size"), sessions=("session", "nunique"))
