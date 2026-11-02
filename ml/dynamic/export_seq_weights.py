"""
Export the dynamic-sign network (../data/dynamic/seq_model.keras) to JSON so the
Flutter app runs it in plain Dart, like the static model (export_weights.py).

Writes ../data/dynamic/seq_model.json and, if ../../sign_learn exists,
../../sign_learn/assets/seq_model.json

The JSON holds one test sequence (input + Keras output) so the app can check
that the Dart GRU/LSTM computes the same numbers (DynamicSignClassifier.selfTest).

    python export_seq_weights.py
    python export_seq_weights.py --no-app   (do not copy into the app)
"""
import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf

import dataset
from seq_features import T, DURATION, N_FEATURES

APP_ASSETS = Path(__file__).resolve().parents[2] / "sign_learn" / "assets"
r = lambda a: np.round(np.asarray(a, dtype=np.float64), 6).tolist()

model = tf.keras.models.load_model(dataset.DATA / "seq_model.keras")
labels = (dataset.DATA / "seq_labels.txt").read_text().split()

layers = []
for layer in model.layers:
    if isinstance(layer, tf.keras.layers.GRU):
        if not layer.reset_after:
            raise SystemExit("Only GRU(reset_after=True), the Keras default, is supported.")
        kernel, recurrent, bias = layer.get_weights()  # bias: (2, 3u)
        layers.append({"type": "gru", "units": layer.units, "kernel": r(kernel),
                       "recurrent": r(recurrent), "bias_in": r(bias[0]), "bias_rec": r(bias[1])})
    elif isinstance(layer, tf.keras.layers.LSTM):
        kernel, recurrent, bias = layer.get_weights()
        layers.append({"type": "lstm", "units": layer.units, "kernel": r(kernel),
                       "recurrent": r(recurrent), "bias": r(bias)})
    elif isinstance(layer, tf.keras.layers.Dense):
        w, b = layer.get_weights()
        layers.append({"type": "dense", "w": r(w), "b": r(b),
                       "activation": layer.activation.__name__})
    # Dropout does nothing at prediction time.

x = dataset.load()[0].feats()[None].astype(np.float32)
y = model.predict(x, verbose=0)[0]
out = {
    "labels": labels,
    "frames": T,
    "features": N_FEATURES,
    "duration": DURATION,
    "layers": layers,
    "test": {"input": r(x[0]), "output": r(y)},
}
text = json.dumps(out, separators=(",", ":"))
(dataset.DATA / "seq_model.json").write_text(text)
print(f"Saved {dataset.DATA / 'seq_model.json'} ({len(text) / 1024:.0f} KB)")
if APP_ASSETS.exists() and "--no-app" not in sys.argv:
    (APP_ASSETS / "seq_model.json").write_text(text)
    print(f"Copied to {APP_ASSETS / 'seq_model.json'}")
