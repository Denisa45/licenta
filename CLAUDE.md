# Mână în mână – ghid pentru agent

Proiect de licență: aplicație pentru învățarea limbii semnelor române, plus o mână robotică.
Arhitectura completă (servicii, conexiuni, straturi, schema URL, ML, biblioteci,
scalabilitate pe 3 stadii, compromisuri mobile) e descrisă în **docs/ARHITECTURA.md**.
Citește-l înainte să răspunzi la întrebări despre arhitectură și verifică detaliile în cod.

Structura:
- `sign_learn/` – aplicația Flutter (Dart). Ecranele în `lib/screens/`, serviciile HTTP în
  `lib/services/`, recunoașterea pe dispozitiv în `lib/vision/`, `lib/sign_classifier.dart`
  și `lib/dynamic_sign_classifier.dart`. Modelele ML sunt în `assets/*.json`.
- `backend/` – serverul FastAPI + PostgreSQL (`app/routers/`, `app/models.py`), teste în `tests/`.
- `hw/` – Raspberry Pi: `command_listener.py` (cere comenzile de la server), `robot_hand.py` (servomotoare pe PCA9685).
- `ml/` – antrenarea modelelor (semne statice), `ml/dynamic/` – semne cu mișcare (GRU/LSTM, DTW).

Proiectul NU mai folosește Firebase. Datele sunt în PostgreSQL, prin API-ul din `backend/`.
Cadrele camerei nu ajung niciodată pe server: recunoașterea se face pe telefon.

Comenzi utile:
- server: `cd backend && docker compose up --build` (documentația API: http://localhost:8000/docs)
- teste server: `cd backend && pytest`
- aplicația: `cd sign_learn && flutter run --dart-define=API_URL=http://<ip>:8000`
