"""
Train the dynamic-sign network: a small GRU (or LSTM) over T=30 frames of
65 features (hand shape + wrist motion, see seq_features.py).

    python train_seq.py               held-out evaluation, saves the model
    python train_seq.py --cell lstm   same with an LSTM instead of a GRU
    python train_seq.py --final       evaluation, then the saved model is
                                      trained again on ALL sequences (for the app)

Output: ../data/dynamic/seq_model.keras, seq_labels.txt, seq_report.txt
Then run export_seq_weights.py to put the model in the app.

Training data is augmented on the fly (each epoch sees new variants):
  - mirrored copy (the other hand)
  - the sign a little faster / slower and shifted in the window
  - a small rotation and size change of the whole hand path
  - a little noise on the landmarks
"""
import argparse
import sys

import numpy as np
import tensorflow as tf
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

import dataset
from seq_features import T, N_FEATURES, features, mirror, resample

parser = argparse.ArgumentParser()
parser.add_argument("--cell", choices=["gru", "lstm"], default="gru")
parser.add_argument("--units", type=int, default=64)
parser.add_argument("--epochs", type=int, default=80)
parser.add_argument("--augment", type=int, default=8, help="augmented copies per sequence and epoch round")
parser.add_argument("--final", action="store_true")
args = parser.parse_args()

rng = np.random.default_rng(42)
tf.random.set_seed(42)

seqs = dataset.load()
if not seqs:
    sys.exit("No sequences found. Record some with record_sequences.py first.")
print(dataset.summary(seqs), "\n")
labels = sorted({s.label for s in seqs})
idx = {l: i for i, l in enumerate(labels)}
n_classes = len(labels)


def augment(s):
    """One random variant of a sequence, as (T, 65) features."""
    times, pts = s.times, s.points.copy()
    # speed / position in the window: keep a random 85-100% part of the recording
    span = times[-1] - times[0]
    keep = rng.uniform(0.85, 1.0) * span
    start = times[0] + rng.uniform(0, span - keep)
    targets = np.linspace(start, start + keep, T)
    flat = pts.reshape(len(times), -1)
    seq = np.stack([np.interp(targets, times, flat[:, j]) for j in range(flat.shape[1])], 1)
    seq = seq.reshape(T, 21, 3)
    # small rotation (in the image plane) and size change around the first wrist
    a = np.deg2rad(rng.uniform(-12, 12))
    k = rng.uniform(0.85, 1.15)
    c = seq[0, 0, :2]
    xy = seq[..., :2] - c
    rot = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    seq[..., :2] = xy @ rot.T * k + c
    seq[..., 2] *= k
    # landmark jitter, relative to the hand size
    size = np.linalg.norm(seq[:, 9] - seq[:, 0], axis=-1).mean()
    seq += rng.normal(0, 0.02 * size, seq.shape)
    f = features(seq)
    return mirror(f) if rng.random() < 0.5 else f


def make_xy(items, aug=0):
    X, y = [], []
    for s in items:
        X.append(s.feats()); y.append(idx[s.label])
        X.append(mirror(s.feats())); y.append(idx[s.label])
        for _ in range(aug):
            X.append(augment(s)); y.append(idx[s.label])
    return np.array(X, dtype=np.float32), np.array(y)


def build():
    Cell = tf.keras.layers.GRU if args.cell == "gru" else tf.keras.layers.LSTM
    m = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(T, N_FEATURES)),
        Cell(args.units),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(32, activation="relu"),
        tf.keras.layers.Dense(n_classes, activation="softmax"),
    ])
    m.compile(optimizer=tf.keras.optimizers.Adam(2e-3),
              loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return m


def train(items, verbose=2):
    m = build()
    rounds = 4
    for r in range(rounds):  # new augmented copies every round
        X, y = make_xy(items, args.augment)
        counts = np.bincount(y, minlength=n_classes)
        weights = {c: len(y) / (n_classes * max(counts[c], 1)) for c in range(n_classes)}
        m.fit(X, y, epochs=args.epochs // rounds, batch_size=32, shuffle=True,
              class_weight=weights, verbose=verbose)
    return m


train_items, test_items = dataset.split(seqs)
print(f"{len(train_items)} training sequences, {len(test_items)} held-out\n")
model = train(train_items)

X_te = np.array([s.feats() for s in test_items], dtype=np.float32)
y_te = np.array([idx[s.label] for s in test_items])
pred = model.predict(X_te, verbose=0).argmax(1)
pred_m = model.predict(mirror(X_te), verbose=0).argmax(1)
report = [
    f"model: {args.cell.upper()}({args.units}), {model.count_params()} parameters",
    f"held-out accuracy: {accuracy_score(y_te, pred):.3f}",
    f"same sequences mirrored (the other hand): {accuracy_score(y_te, pred_m):.3f}",
    "",
    classification_report(y_te, pred, labels=list(range(n_classes)), target_names=labels,
                          digits=3, zero_division=0),
    "Confusion matrix (rows = true sign, columns = predicted):",
    "      " + " ".join(f"{l[:5]:>5}" for l in labels),
]
cm = confusion_matrix(y_te, pred, labels=list(range(n_classes)))
for l, row in zip(labels, cm):
    report.append(f"{l[:5]:>5} " + " ".join(f"{v:5d}" for v in row))
text = "\n".join(report)
print("\n" + text)
(dataset.DATA / f"seq_report_{args.cell}.txt").write_text(text)

if args.final:
    print("\n--final: training the saved model on all sequences...")
    model = train(seqs, verbose=0)

model.save(dataset.DATA / "seq_model.keras")
(dataset.DATA / "seq_labels.txt").write_text("\n".join(labels))
print(f"\nSaved seq_model.keras and seq_labels.txt in {dataset.DATA}")
