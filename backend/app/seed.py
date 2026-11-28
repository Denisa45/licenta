"""Încarcă semnele dintr-un fișier JSON în tabela signs.

Fișierul (ex. data/signs.json, făcut de scripts/export_firestore.py) e o listă:
    [{"id": "A", "name": "A", "unit": "unit1", "order": 1,
      "robot_pose": {"thumb": 1, "index": 0, ...}, ...}, ...]

Rulare manuală (actualizează semnele existente și le adaugă pe cele noi):
    python -m app.seed data/signs.json
"""
import json
import sys
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import Base, SessionLocal, engine
from .models import Sign
from .schemas import SignSchema


def load_signs(db: Session, path: Path) -> int:
    """Adaugă sau actualizează semnele din fișier. Întoarce câte au fost citite."""
    items = json.loads(path.read_text(encoding="utf-8"))
    for item in items:
        data = SignSchema.model_validate(item).model_dump()
        data["sort_order"] = data.pop("order")
        # Fără 'shape', camera caută semnul după nume (A se vede ca A).
        data["shape"] = data["shape"] or data["name"]
        sign = db.get(Sign, data["id"])
        if sign is None:
            db.add(Sign(**data))
        else:
            for key, value in data.items():
                setattr(sign, key, value)
    db.commit()
    return len(items)


def seed_if_empty(db: Session, path: Path) -> None:
    """La pornirea serverului: dacă nu există niciun semn, le încarcă din fișier.
    Fără data/signs.json (încă neexportat din Firestore) folosește exemplul
    data/signs.example.json, cu cifrele 0–5."""
    if db.scalar(select(Sign).limit(1)) is not None:
        return
    if not path.exists():
        path = path.with_name("signs.example.json")
    if path.exists():
        n = load_signs(db, path)
        print(f"Am încărcat {n} semne din {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Folosire: python -m app.seed <fisier.json>")
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        print(f"{load_signs(db, Path(sys.argv[1]))} semne încărcate.")
