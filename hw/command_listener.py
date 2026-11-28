"""Preia comenzile de la server și le execută pe mâna robotică.

Aplicația trimite serverului POST /robot/commands {sign_id}. Pi-ul întreabă
serverul la fiecare POLL secunde (POST /robot/commands/next): serverul îi dă cea
mai veche comandă (pending -> processing), cu pozițiile degetelor deja citite
din baza de date. Pentru un cuvânt (ex. DA = D + A) primește câte un pas pe
literă. După mișcare, Pi-ul raportează 'completed' sau 'error'.
Starea mâinii (idle / moving / offline) se trimite cu PUT /robot/status.

Comenzile prea vechi (trimise cât timp Pi-ul era oprit) sunt marcate 'expired'
de server, deci mâna nu arată semne vechi la pornire.

Rulare pe Pi:
  SERVER_URL=http://192.168.1.10:8000 ROBOT_API_KEY=... python3 hw/command_listener.py
ROBOT_API_KEY trebuie să fie aceeași cu cea din backend/.env. Nu o pune în Git.
"""
import os
import signal
import time

import requests

from robot_hand import release, set_fingers

SERVER_URL = os.environ.get("SERVER_URL", "http://localhost:8000").rstrip("/")
API_KEY = os.environ.get("ROBOT_API_KEY", "")
HOLD = float(os.environ.get("ROBOT_HOLD", 5))  # secunde cât ține semnul, apoi mâna se deschide
LETTER_HOLD = float(os.environ.get("ROBOT_LETTER_HOLD", 2))  # secunde pe literă, la cuvinte
POLL = float(os.environ.get("ROBOT_POLL", 0.5))  # cât de des întreabă serverul (secunde)

# chei robot_pose din baza de date -> numele degetelor din robot_hand.py
POSE_KEYS = {"thumb": "police", "index": "aratator", "middle": "mijlociu",
             "ring": "inelar", "pinky": "mic"}

http = requests.Session()
http.headers["X-Robot-Key"] = API_KEY


def api(method, path, **kwargs):
    r = http.request(method, f"{SERVER_URL}{path}", timeout=10, **kwargs)
    r.raise_for_status()
    return r


def set_status(state, sign_id=None):
    try:
        api("PUT", "/robot/status", json={"state": state, "current_sign": sign_id})
    except requests.RequestException as e:
        print(f"Nu am putut trimite starea '{state}': {e}")


def open_fingers(pose):
    """Degetele întinse (valoarea 1 în robot_pose)."""
    return [POSE_KEYS[k] for k, v in (pose or {}).items() if k in POSE_KEYS and v == 1]


def execute(job):
    sign_id = job["sign_id"]
    hold = LETTER_HOLD if job["is_word"] else HOLD
    try:
        set_status("moving", sign_id)
        for step in job["steps"]:
            fingers = open_fingers(step["robot_pose"])
            print(f"Semnul {step['sign_id']}: {fingers}")
            set_fingers(fingers)
            time.sleep(hold)
        set_fingers(list(POSE_KEYS.values()))   # înapoi la mâna deschisă
        release()
        result = {"status": "completed"}
    except Exception as e:
        release()
        print(f"Eroare la {sign_id}: {e}")
        result = {"status": "error", "error_message": str(e)}
    try:
        api("POST", f"/robot/commands/{job['id']}/result", json=result)
    except requests.RequestException as e:
        print(f"Nu am putut raporta rezultatul comenzii {job['id']}: {e}")
    set_status("idle")


def main():
    if not API_KEY:
        raise SystemExit("Lipsește ROBOT_API_KEY (aceeași ca în backend/.env).")
    # systemctl stop trimite SIGTERM: oprește-te ca la Ctrl+C, cu mâna eliberată
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    set_status("idle")
    print(f"Aștept comenzi de la {SERVER_URL}... (Ctrl+C pentru oprire)")
    try:
        while True:
            try:
                r = api("POST", "/robot/commands/next")
                if r.status_code == 200:
                    execute(r.json())
                    continue          # poate mai sunt comenzi: întreabă imediat
            except requests.RequestException as e:
                print(f"Serverul nu răspunde: {e}")
                time.sleep(5)
            time.sleep(POLL)
    except KeyboardInterrupt:
        pass
    finally:
        release()
        set_status("offline")


if __name__ == "__main__":
    main()
