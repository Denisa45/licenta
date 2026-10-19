import numpy as np
import pandas as pd

df = pd.read_csv("data/landmarks.csv", dtype={"label": str})

# (label, take id) pairs that don't match their label
DROP = [
    # sign 1: old fist takes
    ("1", 1792257253), ("1", 1792257428), ("1", 1792257432), ("1", 1792257436),
    # sign 1: new takes that are a fist, or a 2
    ("1", 1792257662), ("1", 1792257663), ("1", 1792257664), ("1", 1792257672),
    # sign 3 and 4: takes with the wrong shape
    ("3", 1792257288), ("3", 1792257475),
    ("4", 1792257298),
        ("3", 1792349490),   # new sign 3 take: ring finger up, thumb folded
    ("1", 1792257667),   # sign 1 take with the thumb out
        ("3", 1792350745),
    ("2", 1792257450),   # sign 2 take with the thumb out most of the time
]
  
mask = pd.Series(False, index=df.index)
for label, take in DROP:
    mask |= (df["label"] == label) & (df["take"] == take)

# Sign 2 must have the thumb tucked, sign 3 must have it out: drop the frames
# where the thumb does not match (same thumb test as check_takes.py).
p = df[[c for c in df.columns if c not in ("label", "take")]].values.reshape(-1, 21, 3)
thumb_out = np.linalg.norm(p[:, 4] - p[:, 17], axis=1) > np.linalg.norm(p[:, 3] - p[:, 17], axis=1)
mask |= ((df["label"] == "2") & thumb_out) | ((df["label"] == "3") & ~thumb_out)

clean = df[~mask]
clean.to_csv("data/landmarks_clean.csv", index=False)
print(clean.groupby("label")["take"].agg(samples="size", takes="nunique"))