"""Conexiunea la baza de date (SQLAlchemy)."""
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Iterator[Session]:
    """O sesiune de bază de date pentru fiecare cerere HTTP."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
