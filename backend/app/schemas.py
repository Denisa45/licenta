"""Formatul JSON al cererilor și răspunsurilor (Pydantic)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---- conturi ----

class Credentials(BaseModel):
    email: str
    password: str


class UserOut(ORM):
    id: int
    email: str
    role: str
    created_at: datetime


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# ---- semne ----

class SignSchema(BaseModel):
    """Un semn, cu aceleași câmpuri ca în vechea colecție Firestore 'signs'.
    În JSON câmpul se numește 'order' (în tabel: sort_order)."""
    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    id: str
    name: str
    description: str = ""
    description_en: str = ""
    unit: str = ""
    difficulty: int = 1
    order: int = Field(0, validation_alias="sort_order", serialization_alias="order")
    verified: bool = False
    robot_pose: dict[str, int] = {}
    shape: str = ""
    letters: list[str] = []
    motion: bool = False


# ---- progres ----

class ProgressOut(ORM):
    sign_id: str
    unit: str
    status: str
    attempts: int
    best_confidence: float
    quiz_score: int
    quiz_total: int
    completed_at: datetime | None
    updated_at: datetime


class CompleteLessonIn(BaseModel):
    confidence: float = Field(ge=0, le=1)
    quiz_score: int = Field(ge=0)
    quiz_total: int = Field(ge=0)


class SessionIn(BaseModel):
    target_sign: str
    predicted_sign: str
    confidence: float = Field(ge=0, le=1)
    success: bool
    step: Literal["lesson", "practice"]
    source: Literal["camera", "debug_skip"] = "camera"


class SessionOut(ORM):
    id: int
    target_sign: str
    predicted_sign: str
    confidence: float
    success: bool
    step: str
    source: str
    timestamp: datetime


# ---- mâna robotică ----

class RobotCommandIn(BaseModel):
    sign_id: str


class RobotCommandOut(ORM):
    id: int
    sign_id: str
    status: str
    error_message: str | None
    created_at: datetime
    started_at: datetime | None
    completed_at: datetime | None


class RobotStep(BaseModel):
    """Un pas pentru mână: o literă dintr-un cuvânt, sau semnul întreg."""
    sign_id: str
    robot_pose: dict[str, int]


class RobotJob(BaseModel):
    """Comanda preluată de Pi, cu pozițiile deja citite din tabela signs."""
    id: int
    sign_id: str
    is_word: bool
    steps: list[RobotStep]


class RobotResultIn(BaseModel):
    status: Literal["completed", "error"]
    error_message: str | None = None


class RobotStatusIn(BaseModel):
    state: Literal["idle", "moving", "offline"]
    current_sign: str | None = None


class RobotStatusOut(ORM):
    state: str
    current_sign: str | None
    updated_at: datetime
