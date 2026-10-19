import pandas as pd, numpy as np
df = pd.read_csv("data/landmarks.csv", dtype={"label": str})
print(len(df.columns), list(df.columns[:6]))
p = df.drop(columns=["label", "take"]).iloc[0].values.reshape(21, 3)
print("wrist:", p[0].round(3))
print("wrist to middle-finger base:", round(float(np.linalg.norm(p[9])), 3))
