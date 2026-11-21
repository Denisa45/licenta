"""/auth: creare cont, autentificare, utilizatorul curent.

Erorile au aceleași coduri ca Firebase Auth (ex. 'email-already-in-use'),
ca aplicația să arate aceleași mesaje ca înainte.
"""
from email_validator import EmailNotValidError, validate_email
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User
from ..schemas import Credentials, TokenOut, UserOut
from ..security import create_token, current_user, hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])

MIN_PASSWORD = 6


def _normalize_email(email: str) -> str:
    try:
        return validate_email(email.strip(), check_deliverability=False).normalized.lower()
    except EmailNotValidError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="invalid-email")


@router.post("/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(body: Credentials, db: Session = Depends(get_db)):
    email = _normalize_email(body.email)
    if len(body.password) < MIN_PASSWORD:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="weak-password")
    if db.scalar(select(User).where(func.lower(User.email) == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="email-already-in-use")

    user = User(email=email, password_hash=hash_password(body.password), role="user")
    db.add(user)
    db.commit()
    return TokenOut(access_token=create_token(user), user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
def login(body: Credentials, db: Session = Depends(get_db)):
    email = body.email.strip().lower()
    user = db.scalar(select(User).where(func.lower(User.email) == email))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="invalid-credential")
    return TokenOut(access_token=create_token(user), user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user)):
    return user
