"""/robot: comenzile pentru mâna robotică.

Aplicația (utilizator autentificat):
    POST /robot/commands          {sign_id}  -> comanda, cu status 'pending'
    GET  /robot/commands/{id}                -> statusul comenzii
    GET  /robot/status                       -> starea mâinii

Raspberry Pi-ul (antetul X-Robot-Key, vezi hw/command_listener.py):
    POST /robot/commands/next                -> preia cea mai veche comandă
                                                (pending -> processing) sau 204
    POST /robot/commands/{id}/result         -> 'completed' sau 'error'
    PUT  /robot/status                       -> idle | moving | offline
"""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import RobotCommand, RobotStatus, Sign, User, utcnow
from ..schemas import (
    RobotCommandIn,
    RobotCommandOut,
    RobotJob,
    RobotResultIn,
    RobotStatusIn,
    RobotStatusOut,
    RobotStep,
)
from ..security import current_user, robot_key

router = APIRouter(prefix="/robot", tags=["robot"])


# ---- aplicația ----

@router.post("/commands", response_model=RobotCommandOut, status_code=status.HTTP_201_CREATED)
def create_command(body: RobotCommandIn, db: Session = Depends(get_db),
                   user: User = Depends(current_user)):
    if db.get(Sign, body.sign_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="sign-not-found")
    cmd = RobotCommand(sign_id=body.sign_id, user_id=user.id, status="pending")
    db.add(cmd)
    db.commit()
    return cmd


@router.get("/commands/{command_id}", response_model=RobotCommandOut)
def get_command(command_id: int, db: Session = Depends(get_db),
                user: User = Depends(current_user)):
    cmd = db.get(RobotCommand, command_id)
    if cmd is None or cmd.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="command-not-found")
    return cmd


@router.get("/status", response_model=RobotStatusOut)
def get_status(db: Session = Depends(get_db), _: User = Depends(current_user)):
    return db.get(RobotStatus, "hand") or RobotStatus(
        id="hand", state="offline", current_sign=None, updated_at=utcnow()
    )


# ---- Raspberry Pi ----

def _steps(db: Session, sign: Sign) -> list[RobotStep]:
    """Un cuvânt (letters = ["D", "A"]) devine câte un pas pe literă."""
    ids = sign.letters or [sign.id]
    steps = []
    for sid in ids:
        s = sign if sid == sign.id else db.get(Sign, sid)
        if s is None:
            raise ValueError(f"semn necunoscut: {sid}")
        steps.append(RobotStep(sign_id=s.id, robot_pose=s.robot_pose or {}))
    return steps


@router.post("/commands/next", response_model=RobotJob,
             responses={204: {"description": "Nicio comandă în așteptare"}},
             dependencies=[Depends(robot_key)])
def next_command(db: Session = Depends(get_db)):
    """Preia cea mai veche comandă 'pending'. Comenzile prea vechi devin 'expired',
    ca mâna să nu arate semne vechi la pornire. Vârsta se măsoară cu ceasul
    serverului, nu cu al Pi-ului."""
    now = utcnow()
    max_age = timedelta(seconds=settings.robot_command_max_age)
    while True:
        cmd = db.scalar(
            select(RobotCommand)
            .where(RobotCommand.status == "pending")
            .order_by(RobotCommand.created_at, RobotCommand.id)
            .limit(1)
            .with_for_update(skip_locked=True)  # o comandă e preluată o singură dată
        )
        if cmd is None:
            db.commit()
            return Response(status_code=status.HTTP_204_NO_CONTENT)
        if now - cmd.created_at > max_age:
            cmd.status = "expired"
            cmd.completed_at = now
            db.commit()
            continue
        try:
            steps = _steps(db, cmd.sign)
        except ValueError as e:
            cmd.status = "error"
            cmd.error_message = str(e)
            cmd.completed_at = now
            db.commit()
            continue
        cmd.status = "processing"
        cmd.started_at = now
        db.commit()
        return RobotJob(id=cmd.id, sign_id=cmd.sign_id,
                        is_word=bool(cmd.sign.letters), steps=steps)


@router.post("/commands/{command_id}/result", response_model=RobotCommandOut,
             dependencies=[Depends(robot_key)])
def command_result(command_id: int, body: RobotResultIn, db: Session = Depends(get_db)):
    cmd = db.get(RobotCommand, command_id)
    if cmd is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="command-not-found")
    cmd.status = body.status
    cmd.error_message = body.error_message
    cmd.completed_at = utcnow()
    db.commit()
    return cmd


@router.put("/status", response_model=RobotStatusOut, dependencies=[Depends(robot_key)])
def put_status(body: RobotStatusIn, db: Session = Depends(get_db)):
    row = db.get(RobotStatus, "hand")
    if row is None:
        row = RobotStatus(id="hand")
        db.add(row)
    row.state = body.state
    row.current_sign = body.current_sign
    row.updated_at = utcnow()
    db.commit()
    return row
