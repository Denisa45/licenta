"""Ascultă comenzile din Firestore și le execută pe mâna robotică.

Aplicația scrie în robot_commands un document {sign_id, uid, status: "pending",
created_at}. Pi-ul îl preia (pending -> processing), citește robot_pose din
signs/{sign_id}, arată semnul, apoi pune status = "completed" sau "error".
Starea mâinii se scrie în robot_status/hand.

Rulare pe Pi:
  python3 hw/command_listener.py
Cheia contului de serviciu: ~/firebase-key.json (sau calea din FIREBASE_KEY).
Nu o pune niciodată în Git.
"""
import os
import queue
import signal
import time

import firebase_admin
from firebase_admin import credentials, firestore

from robot_hand import release, set_fingers

KEY_PATH = os.environ.get("FIREBASE_KEY", os.path.expanduser("~/firebase-key.json"))
HOLD = float(os.environ.get("ROBOT_HOLD", 5))  # secunde cât ține semnul, apoi mâna se deschide
# Comenzile mai vechi de atât (ex. trimise cât timp Pi-ul era oprit) nu se mai
# execută, ca mâna să nu arate semne vechi la pornire. Aplicația așteaptă 20 s.
MAX_AGE = 15

# chei robot_pose din Firestore -> numele degetelor din robot_hand.py
POSE_KEYS = {"thumb": "police", "index": "aratator", "middle": "mijlociu",
             "ring": "inelar", "pinky": "mic"}

firebase_admin.initialize_app(credentials.Certificate(KEY_PATH))
db = firestore.client()
status_doc = db.collection("robot_status").document("hand")
pending = queue.Queue()


@firestore.transactional
def claim(transaction, ref):
    """pending -> processing, o singură dată, chiar dacă evenimentul vine de două ori."""
    snap = ref.get(transaction=transaction)
    if not snap.exists or snap.get("status") != "pending":
        return False
    transaction.update(ref, {"status": "processing",
                             "started_at": firestore.SERVER_TIMESTAMP})
    return True


def on_snapshot(docs, changes, read_time):
    # rulează pe firul Firestore; mișcarea se face pe firul principal
    for change in changes:
        if change.type.name != "ADDED":
            continue
        ref = change.document.reference
        if age(change.document, read_time) > MAX_AGE:
            print(f"Comandă veche ignorată: {ref.id}")
            ref.update({"status": "expired"})
        else:
            pending.put(ref)


def age(snap, read_time):
    """Câte secunde are comanda; read_time vine de la server, nu de la ceasul Pi-ului."""
    try:
        return (read_time - snap.get("created_at")).total_seconds()
    except (KeyError, TypeError):
        return 0  # fără created_at încă: o tratăm ca nouă


def set_status(state, sign_id=None):
    status_doc.set({"state": state, "current_sign": sign_id,
                    "updated_at": firestore.SERVER_TIMESTAMP})


def execute(ref):
    if not claim(db.transaction(), ref):
        return
    sign_id = ref.get().get("sign_id")
    try:
        sign = db.collection("signs").document(str(sign_id)).get()
        if not sign.exists:
            raise ValueError(f"semn necunoscut: {sign_id}")
        pose = sign.to_dict().get("robot_pose") or {}
        open_fingers = [POSE_KEYS[k] for k, v in pose.items() if k in POSE_KEYS and v == 1]

        print(f"Semnul {sign_id}: {open_fingers}")
        set_status("moving", sign_id)
        set_fingers(open_fingers)
        time.sleep(HOLD)
        set_fingers(list(POSE_KEYS.values()))   # înapoi la mâna deschisă
        release()

        ref.update({"status": "completed", "completed_at": firestore.SERVER_TIMESTAMP})
    except Exception as e:
        release()
        print(f"Eroare la {sign_id}: {e}")
        ref.update({"status": "error", "error_message": str(e),
                    "completed_at": firestore.SERVER_TIMESTAMP})
    finally:
        set_status("idle")


def main():
    # systemctl stop trimite SIGTERM: oprește-te ca la Ctrl+C, cu mâna eliberată
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    set_status("idle")
    watch = (db.collection("robot_commands")
             .where(filter=firestore.FieldFilter("status", "==", "pending"))
             .on_snapshot(on_snapshot))
    print("Aștept comenzi... (Ctrl+C pentru oprire)")
    try:
        while True:
            execute(pending.get())
    except KeyboardInterrupt:
        pass
    finally:
        watch.unsubscribe()
        release()
        set_status("offline")


if __name__ == "__main__":
    main()
