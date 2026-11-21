"""/progress și /sessions: progresul utilizatorului autentificat.

Fiecare utilizator vede și modifică doar propriile date: user_id vine din
token, nu din cerere (ce făceau înainte regulile de securitate Firestore).
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import PracticeSession, Progress, Sign, User, utcnow
from ..schemas import CompleteLessonIn, ProgressOut, SessionIn, SessionOut
from ..security import current_user

router = APIRouter(tags=["progress"])


def _sign(db: Session, sign_id: str) -> Sign:
    sign = db.get(Sign, sign_id)
    if sign is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="sign-not-found")
    return sign


def _progress(db: Session, user: User, sign: Sign) -> Progress:
    """Rândul de progres pentru (utilizator, semn); îl creează dacă lipsește."""
    row = db.scalar(
        select(Progress).where(Progress.user_id == user.id, Progress.sign_id == sign.id)
    )
    if row is None:
        row = Progress(
            user_id=user.id, sign_id=sign.id, unit=sign.unit,
            status="in_progress", attempts=0, best_confidence=0,
            quiz_score=0, quiz_total=0,
        )
        db.add(row)
    return row


@router.get("/progress", response_model=list[ProgressOut])
def my_progress(db: Session = Depends(get_db), user: User = Depends(current_user)):
    return db.scalars(select(Progress).where(Progress.user_id == user.id)).all()


@router.post("/progress/{sign_id}/start", response_model=ProgressOut)
def start_lesson(sign_id: str, db: Session = Depends(get_db),
                 user: User = Depends(current_user)):
    """Marchează lecția ca începută (rămâne 'completed' dacă era deja terminată)."""
    row = _progress(db, user, _sign(db, sign_id))
    row.updated_at = utcnow()
    db.commit()
    return row


@router.post("/progress/{sign_id}/complete", response_model=ProgressOut)
def complete_lesson(sign_id: str, body: CompleteLessonIn,
                    db: Session = Depends(get_db), user: User = Depends(current_user)):
    """Marchează lecția ca terminată. Cea mai bună încredere nu scade niciodată."""
    row = _progress(db, user, _sign(db, sign_id))
    row.status = "completed"
    row.best_confidence = max(row.best_confidence or 0, body.confidence)
    row.quiz_score = body.quiz_score
    row.quiz_total = body.quiz_total
    if row.completed_at is None:
        row.completed_at = utcnow()
    row.updated_at = utcnow()
    db.commit()
    return row


@router.get("/sessions", response_model=list[SessionOut])
def my_sessions(limit: int = 200, db: Session = Depends(get_db),
                user: User = Depends(current_user)):
    """Ultimele încercări cu camera, cele mai noi primele."""
    return db.scalars(
        select(PracticeSession)
        .where(PracticeSession.user_id == user.id)
        .order_by(PracticeSession.timestamp.desc(), PracticeSession.id.desc())
        .limit(min(max(limit, 1), 1000))
    ).all()


@router.post("/sessions", response_model=SessionOut, status_code=status.HTTP_201_CREATED)
def log_session(body: SessionIn, db: Session = Depends(get_db),
                user: User = Depends(current_user)):
    """Salvează o încercare cu camera; la pasul 'lesson' o numără și pe lecție."""
    sign = _sign(db, body.target_sign)
    session = PracticeSession(user_id=user.id, **body.model_dump())
    db.add(session)
    if body.step == "lesson":
        row = _progress(db, user, sign)
        row.attempts = (row.attempts or 0) + 1
        row.updated_at = utcnow()
    db.commit()
    return session
