import numpy as np
import pandas as pd

df = pd.read_csv("data/landmarks_clean.csv", dtype={"label": str})
features = [c for c in df.columns if c not in ("label", "take")]

EXPECTED = {
    "1": "index",
    "2": "index + middle",
    "3": "thumb + index + middle",
    "4": "index + middle + ring + pinky (thumb folded)",
    "5": "all five",
}


def fingers_up(row):
    p = row[features].values.astype(float).reshape(21, 3)
    n = lambda i: np.linalg.norm(p[i])           # distance from wrist
    d = lambda a, b: np.linalg.norm(p[a] - p[b])
    return pd.Series({
        "thumb": d(4, 17) > d(3, 17),
        "index": n(8) > n(6),
        "middle": n(12) > n(10),
        "ring": n(16) > n(14),
        "pinky": n(20) > n(18),
    })


up = df.apply(fingers_up, axis=1).astype(float)
up["label"] = df["label"]
up["take"] = df["take"]

summary = (up.groupby(["label", "take"])
             .agg(n=("thumb", "size"), thumb=("thumb", "mean"),
                  index=("index", "mean"), middle=("middle", "mean"),
                  ring=("ring", "mean"), pinky=("pinky", "mean"))
             .round(2))
print("Share of frames where each finger is extended (1.0 = always):\n")
print(summary, "\n")
print("Expected:")
for k, v in EXPECTED.items():
    print(f"  sign {k}: {v}")