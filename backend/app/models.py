"""Tabelele bazei de date.

    users              conturile (email + parolă criptată cu bcrypt)
    signs              lecțiile: un semn (A, 1, ...) sau un cuvânt (DA = D + A)
    progress           progresul unui utilizator la un semn (unic pe user + semn)
    practice_sessions  fiecare încercare cu camera
    robot_commands     comenzile trimise mâinii robotice
    robot_status       starea mâinii (un singur rând, id = 'hand')
"""
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import TypeDecorator

from .database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class UTCDateTime(TypeDecorator):
    """Dată și oră mereu în UTC, cu fusul orar inclus (și pe SQLite, care îl pierde)."""
    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is not None and value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(20), default="user")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Sign(Base):
    __tablename__ = "signs"

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    description: Mapped[str] = mapped_column(Text, default="")
    description_en: Mapped[str] = mapped_column(Text, default="")
    unit: Mapped[str] = mapped_column(String(50), default="")
    difficulty: Mapped[int] = mapped_column(Integer, default=1)
    # "order" e cuvânt rezervat în SQL, așa că în tabel coloana e sort_order.
    sort_order: Mapped[int] = mapped_column(Integer, default=0, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    # {"thumb": 0|1, "index": 0|1, "middle": 0|1, "ring": 0|1, "pinky": 0|1}
    robot_pose: Mapped[dict] = mapped_column(JSON, default=dict)
    # Eticheta modelului ML pe care camera trebuie s-o vadă (V = forma lui 2).
    shape: Mapped[str] = mapped_column(String(50), default="")
    # La cuvinte: id-urile literelor, în ordine (DA: ["D", "A"]).
    letters: Mapped[list] = mapped_column(JSON, default=list)
    # Semn cu mișcare, verificat de modelul de secvențe.
    motion: Mapped[bool] = mapped_column(Boolean, default=False)


class Progress(Base):
    __tablename__ = "progress"
    __table_args__ = (UniqueConstraint("user_id", "sign_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    sign_id: Mapped[str] = mapped_column(ForeignKey("signs.id", ondelete="CASCADE"))
    unit: Mapped[str] = mapped_column(String(50), default="")
    status: Mapped[str] = mapped_column(String(20), default="in_progress")
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    best_confidence: Mapped[float] = mapped_column(Float, default=0)
    quiz_score: Mapped[int] = mapped_column(Integer, default=0)
    quiz_total: Mapped[int] = mapped_column(Integer, default=0)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, onupdate=utcnow
    )


class PracticeSession(Base):
    __tablename__ = "practice_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_sign: Mapped[str] = mapped_column(String(50))
    predicted_sign: Mapped[str] = mapped_column(String(50))
    confidence: Mapped[float] = mapped_column(Float)
    success: Mapped[bool] = mapped_column(Boolean)
    step: Mapped[str] = mapped_column(String(20))  # 'lesson' sau 'practice'
    source: Mapped[str] = mapped_column(String(20), default="camera")  # sau 'debug_skip'
    timestamp: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class RobotCommand(Base):
    __tablename__ = "robot_commands"

    id: Mapped[int] = mapped_column(primary_key=True)
    sign_id: Mapped[str] = mapped_column(ForeignKey("signs.id", ondelete="CASCADE"))
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # pending -> processing -> completed | error ; sau expired
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)

    sign: Mapped[Sign] = relationship()


class RobotStatus(Base):
    __tablename__ = "robot_status"

    id: Mapped[str] = mapped_column(String(20), primary_key=True, default="hand")
    state: Mapped[str] = mapped_column(String(20), default="offline")  # idle | moving | offline
    current_sign: Mapped[str | None] = mapped_column(String(50))
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, onupdate=utcnow
    )
