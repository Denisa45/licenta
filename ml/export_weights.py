"""
Export the trained network (data/sign_model.keras) to JSON so the Flutter app
can run it in plain Dart, with no TFLite plugin.

Writes: data/sign_model.json
        and, if ../sign_learn exists, ../sign_learn/assets/sign_model.json

The JSON also holds one test sample (input + the Keras output), so the Dart code
can check that it computes the same numbers as Python.

Run from the ml folder, in the training environment:
    .venv\\Scripts\\activate
    python export_weights.py
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf

ML_DIR = Path(__file__).resolve().parent
DATA = ML_DIR / "data"
APP_ASSETS = ML_DIR.parent / "sign_learn" / "assets"

model = tf.keras.models.load_model(DATA / "sign_model.keras")
labels = (DATA / "labels.txt").read_text().split()

layers = []
for layer in model.layers:
    if isinstance(layer, tf.keras.layers.Dense):
        w, b = layer.get_weights()  # w shape: (inputs, outputs)
        layers.append({
            "w": np.round(w, 6).tolist(),
            "b": np.round(b, 6).tolist(),
            "activation": layer.activation.__name__,
        })
    # Dropout layers do nothing at prediction time, so they are skipped.

# One real sample to verify the Dart implementation against
df = pd.read_csv(DATA / "landmarks_clean.csv", dtype={"label": str})
features = [c for c in df.columns if c not in ("label", "take")]
x = df[features].values.astype("float32")[:1]
y = model.predict(x, verbose=0)[0]

out = {
    "labels": labels,
    "layers": layers,
    "test": {
        "input": np.round(x[0], 6).tolist(),
        "output": np.round(y, 6).tolist(),
        "label": str(df["label"].iloc[0]),
    },
}

text = json.dumps(out)
(DATA / "sign_model.json").write_text(text)
print(f"Saved {DATA / 'sign_model.json'}  ({len(text) / 1024:.1f} KB)")

if APP_ASSETS.parent.exists():
    APP_ASSETS.mkdir(exist_ok=True)
    (APP_ASSETS / "sign_model.json").write_text(text)
    print(f"Copied to {APP_ASSETS / 'sign_model.json'}")
else:
    print("Folder ../sign_learn not found: copy data/sign_model.json into the app's assets folder yourself.")
