"""Testele rulează pe baza din TEST_DATABASE_URL (ex. un PostgreSQL de test)
sau, implicit, pe un fișier SQLite temporar."""
import os
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL", f"sqlite:///{_tmp}/test.db"
)
os.environ["ROBOT_API_KEY"] = "cheie-test"
os.environ["JWT_SECRET"] = "secret-test"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture()
def client():
    Base.metadata.drop_all(engine)
    with TestClient(app) as c:  # pornirea creează tabelele și încarcă semnele exemplu
        yield c
    Base.metadata.drop_all(engine)


def register(client, email="ana@example.com", password="parola123"):
    r = client.post("/auth/register", json={"email": email, "password": password})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}
