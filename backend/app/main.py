"""Serverul aplicației „Mână în mână” (FastAPI).

Pornire (din folderul backend/):
    uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
Documentația interactivă a API-ului: http://localhost:8000/docs
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import Base, SessionLocal, engine
from .routers import auth, progress, robot, signs
from .seed import seed_if_empty


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Creează tabelele care lipsesc, apoi încarcă semnele la prima pornire.
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        seed_if_empty(db, settings.signs_file)
    yield


app = FastAPI(
    title="Mână în mână – API",
    description="Server pentru aplicația de învățare a limbajului semnelor "
                "și pentru mâna robotică.",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(signs.router)
app.include_router(progress.router)
app.include_router(robot.router)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok"}
