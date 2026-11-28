from datetime import timedelta

from app.database import SessionLocal
from app.models import RobotCommand, Sign, utcnow

from .conftest import register

ROBOT = {"X-Robot-Key": "cheie-test"}


# ---- conturi ----

def test_register_login_me(client):
    h = register(client, "Ana@Example.com")
    assert client.get("/auth/me", headers=h).json()["email"] == "ana@example.com"

    r = client.post("/auth/login", json={"email": "ana@example.com", "password": "parola123"})
    assert r.status_code == 200 and r.json()["access_token"]


def test_auth_errors_use_firebase_codes(client):
    register(client)
    cases = [
        ("/auth/register", "ana@example.com", "parola123", "email-already-in-use"),
        ("/auth/register", "nu-e-email", "parola123", "invalid-email"),
        ("/auth/register", "b@example.com", "123", "weak-password"),
        ("/auth/login", "ana@example.com", "gresita", "invalid-credential"),
        ("/auth/login", "nimeni@example.com", "parola123", "invalid-credential"),
    ]
    for path, email, password, code in cases:
        r = client.post(path, json={"email": email, "password": password})
        assert r.json()["detail"] == code, (path, email, r.text)


def test_requires_token(client):
    assert client.get("/signs").status_code == 401
    assert client.get("/signs", headers={"Authorization": "Bearer x"}).status_code == 401


# ---- semne ----

def test_signs_seeded_in_order(client):
    h = register(client)
    signs = client.get("/signs", headers=h).json()
    assert [s["id"] for s in signs] == ["0", "1", "2", "3", "4", "5"]
    assert signs[2]["order"] == 3
    assert signs[2]["shape"] == "2"
    assert signs[2]["robot_pose"] == {"thumb": 0, "index": 1, "middle": 1, "ring": 0, "pinky": 0}


# ---- progres ----

def test_lesson_flow(client):
    h = register(client)
    assert client.get("/progress", headers=h).json() == []

    client.post("/progress/1/start", headers=h)
    for _ in range(2):
        r = client.post("/sessions", headers=h, json={
            "target_sign": "1", "predicted_sign": "1", "confidence": 0.9,
            "success": True, "step": "lesson"})
        assert r.status_code == 201
    client.post("/sessions", headers=h, json={
        "target_sign": "2", "predicted_sign": "2", "confidence": 0.8,
        "success": True, "step": "practice"})

    r = client.post("/progress/1/complete", headers=h,
                    json={"confidence": 0.9, "quiz_score": 3, "quiz_total": 4})
    first_done = r.json()["completed_at"]
    # a doua oară, cu încredere mai mică: best_confidence și completed_at rămân
    r = client.post("/progress/1/complete", headers=h,
                    json={"confidence": 0.5, "quiz_score": 4, "quiz_total": 4})
    p = r.json()
    assert p["status"] == "completed"
    assert p["attempts"] == 2  # doar sesiunile 'lesson' se numără
    assert p["best_confidence"] == 0.9
    assert p["quiz_score"] == 4
    assert p["completed_at"] == first_done

    # start după terminare nu strică 'completed'
    assert client.post("/progress/1/start", headers=h).json()["status"] == "completed"

    sessions = client.get("/sessions", headers=h).json()
    assert len(sessions) == 3 and sessions[0]["step"] == "practice"


def test_users_see_only_their_data(client):
    ana = register(client, "ana@example.com")
    ion = register(client, "ion@example.com")
    client.post("/progress/1/start", headers=ana)
    client.post("/sessions", headers=ana, json={
        "target_sign": "1", "predicted_sign": "1", "confidence": 1,
        "success": True, "step": "practice"})
    assert client.get("/progress", headers=ion).json() == []
    assert client.get("/sessions", headers=ion).json() == []

    cmd = client.post("/robot/commands", headers=ana, json={"sign_id": "1"}).json()
    assert client.get(f"/robot/commands/{cmd['id']}", headers=ion).status_code == 404


# ---- mâna robotică ----

def test_robot_command_flow(client):
    h = register(client)
    cmd = client.post("/robot/commands", headers=h, json={"sign_id": "2"}).json()
    assert cmd["status"] == "pending"

    assert client.post("/robot/commands/next").status_code == 401  # fără cheie
    job = client.post("/robot/commands/next", headers=ROBOT).json()
    assert job["id"] == cmd["id"] and not job["is_word"]
    assert job["steps"][0]["robot_pose"]["index"] == 1
    assert client.get(f"/robot/commands/{cmd['id']}", headers=h).json()["status"] == "processing"
    assert client.post("/robot/commands/next", headers=ROBOT).status_code == 204

    client.post(f"/robot/commands/{cmd['id']}/result", headers=ROBOT,
                json={"status": "completed"})
    assert client.get(f"/robot/commands/{cmd['id']}", headers=h).json()["status"] == "completed"

    client.put("/robot/status", headers=ROBOT, json={"state": "idle"})
    assert client.get("/robot/status", headers=h).json()["state"] == "idle"


def test_robot_word_and_expired(client):
    h = register(client)
    with SessionLocal() as db:
        db.add(Sign(id="DOI", name="DOI", unit="unit2", sort_order=10,
                    robot_pose={}, letters=["1", "2"]))
        db.commit()

    old = client.post("/robot/commands", headers=h, json={"sign_id": "1"}).json()
    with SessionLocal() as db:
        db.get(RobotCommand, old["id"]).created_at = utcnow() - timedelta(minutes=5)
        db.commit()
    word = client.post("/robot/commands", headers=h, json={"sign_id": "DOI"}).json()

    job = client.post("/robot/commands/next", headers=ROBOT).json()
    assert job["id"] == word["id"] and job["is_word"]
    assert [s["sign_id"] for s in job["steps"]] == ["1", "2"]
    assert client.get(f"/robot/commands/{old['id']}", headers=h).json()["status"] == "expired"
