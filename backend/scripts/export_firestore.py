"""Exportă semnele din Firestore într-un fișier JSON pentru noul server.

Se rulează O SINGURĂ DATĂ, pe calculatorul tău, cu cheia contului de serviciu
Firebase (Firebase Console -> Project settings -> Service accounts ->
Generate new private key). Cheia NU se pune niciodată în Git.

    pip install firebase-admin
    python backend/scripts/export_firestore.py --key ~/firebase-key.json

Rezultatul: backend/data/signs.json, încărcat de server la prima pornire
(sau oricând cu: python -m app.seed data/signs.json, din folderul backend/).

Conturile NU se pot exporta cu parole (Firebase nu le dă), așa că utilizatorii
își creează din nou contul în aplicație. Progresul vechi poate fi exportat cu
--with-progress, doar pentru arhivă (nu e importat automat).
"""
import argparse
import json
from datetime import datetime
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

OUT_DIR = Path(__file__).resolve().parent.parent / "data"

SIGN_FIELDS = ["name", "description", "description_en", "unit", "difficulty",
               "order", "verified", "robot_pose", "shape", "letters", "motion"]


def plain(value):
    """Valori Firestore -> JSON (datele calendaristice devin text ISO)."""
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items()}
    if isinstance(value, list):
        return [plain(v) for v in value]
    return value


def export_signs(db) -> list[dict]:
    signs = []
    for doc in db.collection("signs").stream():
        data = doc.to_dict() or {}
        sign = {"id": doc.id}
        for field in SIGN_FIELDS:
            if field in data:
                sign[field] = plain(data[field])
        sign.setdefault("name", doc.id)
        sign["robot_pose"] = {k: int(v) for k, v in (sign.get("robot_pose") or {}).items()}
        signs.append(sign)
    signs.sort(key=lambda s: (s.get("order", 0), s["id"]))
    return signs


def export_collection(db, name: str) -> list[dict]:
    return [{"id": d.id, **plain(d.to_dict() or {})} for d in db.collection(name).stream()]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key", required=True, help="calea către cheia JSON Firebase")
    parser.add_argument("--with-progress", action="store_true",
                        help="exportă și progress/ și practice_sessions/ (arhivă)")
    args = parser.parse_args()

    firebase_admin.initialize_app(credentials.Certificate(str(Path(args.key).expanduser())))
    db = firestore.client()
    OUT_DIR.mkdir(exist_ok=True)

    signs = export_signs(db)
    out = OUT_DIR / "signs.json"
    out.write_text(json.dumps(signs, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{len(signs)} semne -> {out}")

    if args.with_progress:
        for name in ("progress", "practice_sessions"):
            rows = export_collection(db, name)
            path = OUT_DIR / f"firestore_{name}.json"
            path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"{len(rows)} documente {name} -> {path}")


if __name__ == "__main__":
    main()
