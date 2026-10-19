"""
Train a small neural network on data/landmarks_clean.csv and export it to TFLite
(so it can run inside the Flutter app, unlike the RandomForest .joblib).

Uses the SAME split as train_model.py: for every sign, the last "take" is the
held-out test set, all earlier takes are training data.

Run from the same folder as train_model.py, with the venv active:
    pip install tensorflow
    python train_nn.py

Output: data/sign_model.tflite, data/sign_model.keras, data/labels.txt

    python train_nn.py --final
first prints the same held-out evaluation, then trains the saved model again on
ALL takes (more examples, especially for sign 3). Use it for the model in the app,
and report the held-out numbers in the thesis.
"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

CSV = Path("data/landmarks_clean.csv")
OUT = Path("data")
EPOCHS = 60  # fixed: all earlier takes are used for training, none for validation

np.random.seed(42)
tf.random.set_seed(42)

df = pd.read_csv(CSV, dtype={"label": str})
features = [c for c in df.columns if c not in ("label", "take")]
labels = sorted(df["label"].unique())
label_to_idx = {l: i for i, l in enumerate(labels)}
n_classes, n_features = len(labels), len(features)
print(f"{len(df)} rows, {n_features} features, signs: {labels}")

train_parts, test_parts = [], []
for label, g in df.groupby("label"):
    takes = sorted(g["take"].unique())
    if len(takes) < 2:
        print(f"WARNING: sign {label} has only one take, record more.")
        train_parts.append(g)
        continue
    train_parts.append(g[g["take"] != takes[-1]])
    test_parts.append(g[g["take"] == takes[-1]])

train = pd.concat(train_parts)
test = pd.concat(test_parts)

X_tr = train[features].values.astype("float32")
y_tr = train["label"].map(label_to_idx).values
X_te = test[features].values.astype("float32")
y_te = test["label"].map(label_to_idx).values

# Signs with fewer training samples get a bigger weight (see build_and_train).
def build_and_train(X, y, verbose=2):
    counts = np.bincount(y, minlength=n_classes)
    weights = {c: len(y) / (n_classes * counts[c]) for c in range(n_classes)}
    m = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(n_features,)),
        tf.keras.layers.Dense(64, activation="relu"),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(32, activation="relu"),
        tf.keras.layers.Dense(n_classes, activation="softmax"),
    ])
    m.compile(optimizer="adam",
              loss="sparse_categorical_crossentropy",
              metrics=["accuracy"])
    m.fit(X, y, epochs=EPOCHS, batch_size=32, class_weight=weights, verbose=verbose)
    return m


model = build_and_train(X_tr, y_tr)

pred = model.predict(X_te, verbose=0).argmax(axis=1)
print(f"\nTest accuracy (held-out takes): {accuracy_score(y_te, pred):.3f}\n")
print(classification_report(y_te, pred, labels=list(range(n_classes)),
                            target_names=labels, digits=3, zero_division=0))
print("Confusion matrix (rows = true sign, columns = predicted):")
print(pd.DataFrame(confusion_matrix(y_te, pred, labels=list(range(n_classes))),
                   index=labels, columns=labels))

if "--final" in sys.argv:
    print("\n--final: training the saved model on all takes...")
    X_all = df[features].values.astype("float32")
    y_all = df["label"].map(label_to_idx).values
    model = build_and_train(X_all, y_all, verbose=0)

model.save(OUT / "sign_model.keras")
tflite_model = tf.lite.TFLiteConverter.from_keras_model(model).convert()
(OUT / "sign_model.tflite").write_bytes(tflite_model)
(OUT / "labels.txt").write_text("\n".join(labels))
print(f"\nSaved sign_model.tflite ({len(tflite_model) / 1024:.1f} KB) and labels.txt in {OUT}/")
