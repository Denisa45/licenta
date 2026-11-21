"""Parole (bcrypt), tokenuri JWT și verificarea cine face cererea."""
from datetime import timedelta
import secrets

import bcrypt
import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models import User, utcnow

_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    except ValueError:
        return False


def create_token(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "role": user.role,
        "exp": utcnow() + timedelta(days=settings.jwt_expire_days),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def _unauthorized(code: str = "unauthenticated") -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        detail=code,
        headers={"WWW-Authenticate": "Bearer"},
    )


def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """Utilizatorul din tokenul 'Authorization: Bearer ...'."""
    if creds is None:
        raise _unauthorized()
    try:
        payload = jwt.decode(
            creds.credentials, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
        user_id = int(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise _unauthorized("invalid-token")
    user = db.get(User, user_id)
    if user is None:
        raise _unauthorized("user-not-found")
    return user


def robot_key(x_robot_key: str | None = Header(default=None)) -> None:
    """Doar Raspberry Pi-ul, cu cheia din ROBOT_API_KEY, poate prelua comenzi."""
    if x_robot_key is None or not secrets.compare_digest(x_robot_key, settings.robot_api_key):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="invalid-robot-key")
