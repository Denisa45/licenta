# Mână în mână – server (backend)

Serverul aplicației, care înlocuiește Firebase. E scris în **Python (FastAPI)**
și folosește o bază de date **PostgreSQL**.

```
 Aplicația Flutter ──HTTP/JSON + token JWT──►  Server FastAPI  ──SQL──►  PostgreSQL
 (sign_learn/)                                  (backend/)
                                                    ▲
 Raspberry Pi ──HTTP + X-Robot-Key──────────────────┘
 (hw/command_listener.py)
```

| Înainte (Firebase)                          | Acum                                            |
|---------------------------------------------|-------------------------------------------------|
| Firebase Auth (email + parolă)              | `/auth/register`, `/auth/login`: parole criptate cu bcrypt, token JWT |
| Firestore `signs`                           | tabela `signs`, `GET /signs`                    |
| Firestore `progress`, `practice_sessions`   | tabelele `progress`, `practice_sessions`        |
| Regulile de securitate Firestore            | serverul ia utilizatorul din token, deci fiecare vede doar datele lui |
| Firestore `robot_commands` + listener pe Pi | tabela `robot_commands`. Pi-ul cere comenzile de la server |

## Pornire rapidă (cu Docker)

```bash
cd backend
docker compose up --build
```

- API: http://localhost:8000
- Documentația interactivă a API-ului (poți testa fiecare cerere): http://localhost:8000/docs

## Pornire fără Docker

1. Instalează PostgreSQL și creează baza de date:
   ```bash
   sudo -u postgres psql -c "CREATE USER mana WITH PASSWORD 'mana';"
   sudo -u postgres psql -c "CREATE DATABASE mana_in_mana OWNER mana;"
   ```
2. Instalează pachetele Python:
   ```bash
   cd backend
   python -m venv .venv
   source .venv/bin/activate        # Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```
3. Copiază `.env.example` în `.env` și schimbă `JWT_SECRET` și `ROBOT_API_KEY`.
4. Pornește serverul:
   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```

La prima pornire, serverul creează singur tabelele și încarcă semnele din
`data/signs.json`. Dacă fișierul nu există încă, folosește
`data/signs.example.json`, care are doar cifrele 0–5.

## Mutarea semnelor din Firestore (o singură dată)

Lecțiile (descrieri, `robot_pose`, `letters`, `motion`, ordinea) sunt încă
doar în Firestore. Le exporți așa:

1. Firebase Console → Project settings → Service accounts → *Generate new private key*.
   Salvează cheia, de exemplu în `~/firebase-key.json`. **Nu o pune în Git.**
2. Rulează exportul:
   ```bash
   pip install firebase-admin
   python backend/scripts/export_firestore.py --key ~/firebase-key.json
   ```
   Rezultatul e `backend/data/signs.json`.
3. Încarcă semnele în baza de date (merge și dacă serverul a pornit deja):
   ```bash
   cd backend
   python -m app.seed data/signs.json
   ```

Conturile nu se pot muta, pentru că Firebase nu dă parolele. Fiecare
utilizator își creează din nou contul în aplicație.

## Aplicația Flutter

Implicit, aplicația caută serverul la `http://10.0.2.2:8000` pe emulatorul
Android și la `http://localhost:8000` în rest. Pe un telefon real dai adresa
calculatorului din rețeaua Wi-Fi:

```bash
cd sign_learn
flutter run --dart-define=API_URL=http://192.168.1.10:8000
```

## Raspberry Pi

```bash
pip install -r hw/requirements.txt
SERVER_URL=http://192.168.1.10:8000 ROBOT_API_KEY=<aceeași ca în .env> python3 hw/command_listener.py
```

Pentru pornirea automată la boot, vezi `hw/robot-hand.service`.

## API (pe scurt)

| Metodă | Cale                              | Cine        | Ce face |
|--------|-----------------------------------|-------------|---------|
| POST   | `/auth/register`                  | oricine     | creează contul și întoarce tokenul |
| POST   | `/auth/login`                     | oricine     | întoarce tokenul |
| GET    | `/auth/me`                        | utilizator  | contul curent |
| GET    | `/signs`                          | utilizator  | lecțiile, în ordine |
| GET    | `/progress`                       | utilizator  | progresul pe fiecare semn |
| POST   | `/progress/{sign}/start`          | utilizator  | lecție începută |
| POST   | `/progress/{sign}/complete`       | utilizator  | lecție terminată (cea mai bună încredere nu scade) |
| GET    | `/sessions`                       | utilizator  | încercările cu camera |
| POST   | `/sessions`                       | utilizator  | salvează o încercare (la `lesson` crește `attempts`) |
| POST   | `/robot/commands`                 | utilizator  | trimite un semn mâinii |
| GET    | `/robot/commands/{id}`            | utilizator  | statusul comenzii |
| GET    | `/robot/status`                   | utilizator  | starea mâinii |
| POST   | `/robot/commands/next`            | Pi          | preia următoarea comandă (sau 204) |
| POST   | `/robot/commands/{id}/result`     | Pi          | `completed` / `error` |
| PUT    | `/robot/status`                   | Pi          | `idle` / `moving` / `offline` |

Utilizatorul trimite `Authorization: Bearer <token>`, iar Pi-ul trimite `X-Robot-Key: <ROBOT_API_KEY>`.

## Teste

```bash
pip install -r requirements-dev.txt
pytest                                   # pe SQLite, fără nimic instalat
TEST_DATABASE_URL=postgresql+psycopg://mana:mana@localhost:5432/mana_test pytest   # pe PostgreSQL
```
