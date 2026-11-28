"""Setările serverului, citite din variabile de mediu (sau din fișierul .env)."""
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BASE_DIR / ".env", extra="ignore")

    # postgresql+psycopg://utilizator:parola@gazda:port/baza
    database_url: str = "postgresql+psycopg://mana:mana@localhost:5432/mana_in_mana"

    # Cheia cu care se semnează tokenurile JWT. Schimb-o în .env!
    jwt_secret: str = "schimba-ma-in-fisierul-env"
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 30

    # Cheia cu care Raspberry Pi-ul se identifică (antetul X-Robot-Key).
    robot_api_key: str = "schimba-si-cheia-robotului"

    # Comenzile mai vechi de atât (secunde) nu mai sunt trimise mâinii:
    # ex. trimise cât timp Pi-ul era oprit. Aplicația așteaptă 20 s.
    robot_command_max_age: int = 15

    # Fișierul cu semnele, încărcat la pornire dacă tabela signs e goală.
    signs_file: Path = BASE_DIR / "data" / "signs.json"

    # Originile permise pentru Flutter Web (CORS). "*" = oricare.
    cors_origins: list[str] = ["*"]


settings = Settings()
