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
]

mask = pd.Series(False, index=df.index)
for label, take in DROP:
    mask |= (df["label"] == label) & (df["take"] == take)

clean = df[~mask]
clean.to_csv("data/landmarks_clean.csv", index=False)
print(clean.groupby("label")["take"].agg(samples="size", takes="nunique"))