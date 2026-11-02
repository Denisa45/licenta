"""
Baseline for the thesis: nearest neighbour with Dynamic Time Warping (DTW), on
the same features and the same held-out split as train_seq.py. No training:
a sequence gets the sign of the most similar training sequence.

    python dtw_baseline.py

DTW lines the two sequences up in time (one may be faster in some parts), then
adds the frame-to-frame distances along the best alignment. Mirrored copies of
the training sequences are added, like for the network.
"""
import time

import numpy as np
from sklearn.metrics import accuracy_score, classification_report

import dataset
from seq_features import mirror


def dtw(a, b, window=None):
    """DTW distance between (n, d) and (m, d), Euclidean frame distance.
    window: Sakoe-Chiba band (max |i - j|), None = no limit."""
    n, m = len(a), len(b)
    cost = np.linalg.norm(a[:, None, :] - b[None, :, :], axis=-1)
    D = np.full((n + 1, m + 1), np.inf)
    D[0, 0] = 0.0
    w = max(window or max(n, m), abs(n - m))
    for i in range(1, n + 1):
        for j in range(max(1, i - w), min(m, i + w) + 1):
            D[i, j] = cost[i - 1, j - 1] + min(D[i - 1, j], D[i, j - 1], D[i - 1, j - 1])
    return D[n, m] / (n + m)


def main():
    seqs = dataset.load()
    train, test = dataset.split(seqs)
    ref = [(s.feats(), s.label) for s in train] + [(mirror(s.feats()), s.label) for s in train]
    labels = sorted({s.label for s in seqs})

    start = time.time()
    y_true, y_pred = [], []
    for s in test:
        f = s.feats()
        best = min(ref, key=lambda r: dtw(f, r[0], window=6))
        y_true.append(s.label)
        y_pred.append(best[1])
    per = (time.time() - start) / max(len(test), 1)

    text = "\n".join([
        f"1-NN DTW, {len(ref)} reference sequences",
        f"held-out accuracy: {accuracy_score(y_true, y_pred):.3f}",
        f"time per sequence: {per * 1000:.0f} ms",
        "",
        classification_report(y_true, y_pred, labels=labels, digits=3, zero_division=0),
    ])
    print(text)
    (dataset.DATA / "seq_report_dtw.txt").write_text(text)


if __name__ == "__main__":
    main()
