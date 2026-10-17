import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (accuracy_score, classification_report,
                             confusion_matrix)

df = pd.read_csv("data/landmarks_clean.csv", dtype={"label": str})
print("Samples and takes per sign:")
print(df.groupby("label")["take"].agg(samples="size", takes="nunique"), "\n")

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
features = [c for c in df.columns if c not in ("label", "take")]

model = RandomForestClassifier(n_estimators=200, random_state=42)
model.fit(train[features].values, train["label"].values)

pred = model.predict(test[features].values)
labels = sorted(df["label"].unique())

print(f"Test accuracy (held-out takes): "
      f"{accuracy_score(test['label'], pred):.3f}\n")
print(classification_report(test["label"], pred, labels=labels,
                            digits=3, zero_division=0))
print("Confusion matrix (rows = true sign, columns = predicted):")
print(pd.DataFrame(confusion_matrix(test["label"], pred, labels=labels),
                   index=labels, columns=labels))

joblib.dump(model, "data/model_rf.joblib")
print("\nSaved data/model_rf.joblib")