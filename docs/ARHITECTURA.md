# Arhitectura proiectului „Mână în mână”

Aplicație pentru învățarea limbii semnelor române, plus o mână robotică care
arată semnele. Documentul descrie toate componentele, cum comunică între ele,
unde rulează și unde se salvează modelele ML, plus scalabilitatea (stadiul
actual, 10.000 de utilizatori, 1 milion) și compromisurile de arhitectură mobilă.

---

## 1. Componentele, pe scurt

| # | Componentă | Ce este | Ce face | Unde rulează | Cod |
|---|-----------|---------|---------|--------------|-----|
| 1 | **Aplicația mobilă** | Flutter (Dart), compilată nativ ARM | Lecții, quiz, exersare cu camera, progres, butonul „Arată pe mâna robotică” | Telefon / tabletă Android 7.0+ (minSdk 24) | `sign_learn/` |
| 2 | **ML pe dispozitiv** | MediaPipe Hand Landmarker + rețele neuronale scrise în Dart | Camera → 21 de puncte ale mâinii → semnul recunoscut + încredere | În aplicație, local, offline | `sign_learn/lib/vision/`, `sign_classifier.dart`, `dynamic_sign_classifier.dart` |
| 3 | **Server API** | Python, FastAPI + Uvicorn | Conturi, lecții, progres, încercări, coada de comenzi pentru robot | Laptop / server (port 8000) | `backend/app/` |
| 4 | **Baza de date** | PostgreSQL 16 | Datele persistente: utilizatori, semne, progres, sesiuni, comenzi robot | Lângă server (port 5432), în Docker | `backend/app/models.py` |
| 5 | **Controlerul mâinii robotice** | Raspberry Pi + Python | Ia comenzile de la server și mișcă servomotoarele | Raspberry Pi, serviciu systemd | `hw/command_listener.py`, `hw/robot_hand.py` |
| 6 | **Mâna robotică** | 5 servomotoare pe o placă PCA9685 (I²C) | Fiecare deget se întinde (150°) sau se îndoaie (0°) | Hardware | `hw/` |
| 7 | **Pipeline-ul de antrenare ML** | Python: OpenCV, MediaPipe, TensorFlow/Keras, scikit-learn | Înregistrează date, le curăță, antrenează și exportă modelele în JSON | Laptopul dezvoltatorului, offline | `ml/`, `ml/dynamic/` |
| 8 | **Exportul din Firestore** | Script Python rulat o singură dată | Mută lecțiile din vechiul Firebase în noua bază de date | Laptop | `backend/scripts/export_firestore.py` |

---

## 2. Cum se conectează

```
                ┌──────────────────────────── TELEFON / TABLETĂ (Android) ─────────────────────────┐
                │  UI (ecrane Flutter) ─► Servicii (Auth/Sign/Progress/Robot) ─► ApiClient (http) │
                │        ▲                                                                         │
                │  Camera ─► MediaPipe (JNI, CPU) ─► 21 puncte ─► rețea Dart (assets/*.json)       │
                └──────────────────────────────────────┬──────────────────────────────────────────┘
                                                       │ HTTP/JSON (REST), Authorization: Bearer <JWT>
                                                       ▼
   ┌─────────── LAPTOP / SERVER ───────────────────────────────────────────────┐
   │  Uvicorn (ASGI) ─► FastAPI routers: /auth /signs /progress /sessions /robot│
   │                     Pydantic (validare) · PyJWT · bcrypt                    │
   │                     SQLAlchemy ORM ─► psycopg ─► PostgreSQL (TCP 5432)      │
   └──────────────────────────────▲────────────────────────────────────────────┘
                                  │ HTTP polling la 0,5 s, antet X-Robot-Key
                                  │ POST /robot/commands/next · /result · PUT /robot/status
   ┌──────── RASPBERRY PI ────────┴──────────┐
   │ command_listener.py (requests)          │
   │   └► robot_hand.py (adafruit ServoKit)  │──I²C──► PCA9685 ──PWM──► 5 servomotoare (degetele)
   └─────────────────────────────────────────┘

   LAPTOP DEZVOLTATOR (offline): webcam ─► record_takes.py ─► CSV ─► train_nn.py / train_seq.py
                                 ─► export_*_weights.py ─► sign_learn/assets/*.json (intră în aplicație la build)
```

| De la → la | Protocol | Format | Securitate | De ce așa |
|-----------|----------|--------|------------|-----------|
| Aplicație → Server | HTTP REST | JSON | Token JWT (HS256, 30 de zile) în `Authorization: Bearer` | Simplu, fără stare pe server, merge pe orice platformă |
| Pi → Server | HTTP, polling la 0,5 s | JSON | Cheie partajată `X-Robot-Key` | Pi-ul e în spatele unui NAT/Wi-Fi: el inițiază conexiunea, deci serverul nu trebuie să-l poată accesa |
| Server → Baza de date | Protocolul PostgreSQL (TCP 5432) | SQL prin ORM | Utilizator/parolă din `.env` | Date relaționale, tranzacții, chei străine |
| Pi → Mâna robotică | I²C → PWM | Unghiuri 0–150° | – (local) | O placă PCA9685 controlează până la 16 servomotoare |
| Camera → ML | În același proces (JNI/FFI) | 21 × (x, y, z) | Cadrele nu părăsesc telefonul | Confidențialitate, latență mică, funcționează offline |
| Pipeline ML → Aplicație | Fișier copiat la build | JSON cu ponderile rețelei | – | Fără plugin TFLite, același cod pe orice platformă |

### Fluxuri principale

1. **Login:** `LoginScreen` → `AuthService.signIn` → `POST /auth/login` → serverul verifică parola cu bcrypt → întoarce JWT → tokenul se salvează în `shared_preferences` → `AuthGate` deschide aplicația.
2. **Lecție:** `GET /signs` (lista ordonată) → utilizatorul face semnul în fața camerei → **recunoașterea se face local** → `POST /sessions` (doar eticheta + încrederea) → la final `POST /progress/{semn}/complete`.
3. **Mâna robotică:** `POST /robot/commands {sign_id}` → rând `pending` în baza de date → Pi-ul cere `POST /robot/commands/next` (serverul marchează `processing` și trimite pozițiile degetelor; un cuvânt e trimis literă cu literă) → servomotoarele se mișcă → `POST /robot/commands/{id}/result` → aplicația verifică statusul la fiecare secundă și afișează „Gata”.

---

## 3. Straturile software

```
APLICAȚIA (Flutter)                          SERVER (FastAPI)
┌──────────────────────────────────┐         ┌──────────────────────────────────┐
│ Prezentare: screens/, widgets/   │         │ API: routers/ (auth, signs,      │
│  path, lesson, practice,         │         │      progress, robot)            │
│  progress, login; theme, l10n    │         ├──────────────────────────────────┤
├──────────────────────────────────┤         │ Validare: schemas.py (Pydantic)  │
│ Logică / servicii: services/     │  HTTP   ├──────────────────────────────────┤
│  AuthService, SignService,       │ ──────► │ Securitate: security.py          │
│  ProgressService, RobotService   │         │  (JWT, bcrypt, X-Robot-Key)      │
├──────────────────────────────────┤         ├──────────────────────────────────┤
│ Date / rețea: ApiClient, config  │         │ Domeniu / date: models.py (ORM)  │
├──────────────────────────────────┤         ├──────────────────────────────────┤
│ ML: vision/HandTracker,          │         │ Persistență: database.py →       │
│  SignClassifier,                 │         │  PostgreSQL                      │
│  DynamicSignClassifier           │         └──────────────────────────────────┘
├──────────────────────────────────┤
│ Platformă: camera, JNI MediaPipe │
└──────────────────────────────────┘
```

### Schema URL (API REST)

| Metodă | URL | Cine | Răspuns |
|--------|-----|------|---------|
| POST | `/auth/register` | public | `{access_token, user}`; erori `email-already-in-use`, `weak-password`, `invalid-email` |
| POST | `/auth/login` | public | `{access_token, user}`; eroare `invalid-credential` |
| GET | `/auth/me` | JWT | contul curent |
| GET | `/signs`, `/signs/{id}` | JWT | lecțiile ordonate după `order` |
| GET | `/progress` | JWT | progresul utilizatorului pe fiecare semn |
| POST | `/progress/{id}/start`, `/progress/{id}/complete` | JWT | lecție începută / terminată |
| GET / POST | `/sessions` | JWT | încercările cu camera |
| POST | `/robot/commands` | JWT | creează comanda (`pending`) |
| GET | `/robot/commands/{id}` | JWT (doar proprietarul) | statusul comenzii |
| GET | `/robot/status` | JWT | `idle` / `moving` / `offline` |
| POST | `/robot/commands/next` | X-Robot-Key | preia următoarea comandă sau 204 |
| POST | `/robot/commands/{id}/result` | X-Robot-Key | `completed` / `error` |
| PUT | `/robot/status` | X-Robot-Key | actualizează starea mâinii |
| GET | `/health`, `/docs` | public | verificare că serverul merge / documentație Swagger |

### Baza de date

```
users (id, email UNIQUE, password_hash, role, created_at)
  │1
  ├──∞ progress (id, user_id FK, sign_id FK, status, attempts, best_confidence,
  │              quiz_score, quiz_total, completed_at, updated_at)  UNIQUE(user_id, sign_id)
  ├──∞ practice_sessions (id, user_id FK, target_sign, predicted_sign, confidence,
  │                       success, step, source, timestamp)
  └──∞ robot_commands (id, sign_id FK, user_id FK, status, error_message,
                       created_at, started_at, completed_at)
signs (id PK „A”, name, description, description_en, unit, difficulty, sort_order,
       verified, robot_pose JSON, shape, letters JSON, motion)
robot_status (id = „hand”, state, current_sign, updated_at)
```

---

## 4. Machine learning: ce rulează, unde și unde e salvat

### În aplicație (inferență, pe dispozitiv)

1. **`camera`** dă cadrele de la camera frontală.
2. **`hand_landmarker`** (MediaPipe Hand Landmarker, prin JNI, pe CPU, o singură mână, încredere minimă 0,6) dă **21 de puncte (x, y, z)**.
3. **Normalizare:** încheietura ajunge în origine, iar distanța încheietură → baza degetului mijlociu devine 1. Așa rezultatul nu depinde de distanța față de cameră → **63 de valori**.
4. **Semne statice:** `SignClassifier` este o rețea densă 63 → 64 (ReLU) → 32 (ReLU) → 7 (softmax), pentru etichetele `1 2 3 4 5 A L`. Ponderile vin din **`assets/sign_model.json`**, iar calculul e scris direct în Dart (fără TFLite). Probabilitățile sunt netezite în timp.
5. **Semne cu mișcare:** `DynamicSignClassifier` primește 2 s de înregistrare, reeșantionate la 30 de cadre × 65 de valori (forma mâinii plus deplasarea încheieturii). Urmează un GRU(64) (sau LSTM), apoi Dense 32 și softmax, pentru 15 semne (SALUT, MULȚUMESC, DA, NU, MAMA, TATA...). Ponderile sunt în `assets/seq_model.json`, după antrenare.
6. `selfTest()` verifică la pornire că Dart calculează aceleași numere ca Keras (diferență < 1e-4).

**Unde e salvat ce:**

| Ce | Unde | De ce |
|----|------|-------|
| Ponderile modelelor (JSON, ~zeci de KB) | În aplicație, `sign_learn/assets/` (vin odată cu APK-ul) | Merge offline, nu costă nimic pe server, latență de câteva ms |
| Cadrele video | **Nicăieri**: sunt procesate în memorie și aruncate | Confidențialitate (GDPR), zero trafic de rețea |
| Rezultatul unei încercări (eticheta, încrederea, succes) | Pe server, tabela `practice_sessions` | Statistici de progres |
| Datele de antrenare (CSV cu puncte) | În repo, `ml/data/landmarks*.csv`, `ml/data/dynamic/` | Reproductibilitate |
| Modelele originale (`.keras`, `.tflite`) | `ml/data/` | Pentru reantrenare și pentru lucrare |

### Pe laptop (antrenare, offline)

`record_takes.py` / `record_sequences.py` (OpenCV + MediaPipe pe webcam) → CSV → `check_takes.py` / `clean_data.py` (elimină înregistrările greșite) → `train_model.py` (RandomForest, ca bază de comparație) / `train_nn.py` (Keras) / `train_seq.py` (GRU vs LSTM) / `dtw_baseline.py` (1-NN cu DTW, fără antrenare) → `export_weights.py` / `export_seq_weights.py` → JSON în `sign_learn/assets/`.

Evaluarea se face pe date ținute deoparte: ultimul „take”, respectiv ultima zi de înregistrare a fiecărui semn, e setul de test.

---

## 5. Ce face fiecare bibliotecă

### Aplicația (Flutter / Dart)
| Bibliotecă | Rol |
|-----------|-----|
| `flutter` (Material) | Framework UI. Compilează la cod nativ ARM și desenează interfața singur (motorul Impeller/Skia) |
| `camera` | Accesul la camera frontală și fluxul de cadre |
| `hand_landmarker` | Plugin MediaPipe Hand Landmarker (Android, prin JNI/FFI) → 21 de puncte |
| `http` | Cererile REST către server |
| `shared_preferences` | Stocare locală cheie-valoare: tokenul JWT și limba aleasă |
| `cupertino_icons` | Iconițe |
| `flutter_test`, `flutter_lints` | Teste și reguli de stil |

### Serverul (Python)
| Bibliotecă | Rol |
|-----------|-----|
| `fastapi` | Framework web: rute, injecție de dependențe, documentație OpenAPI/Swagger automată |
| `uvicorn` | Serverul ASGI care rulează aplicația FastAPI |
| `pydantic`, `pydantic-settings` | Validează JSON-ul primit și trimis; citește setările din `.env` |
| `SQLAlchemy` | ORM: clase Python ↔ tabele, interogări fără SQL scris de mână, independent de baza de date |
| `psycopg` | Driverul care vorbește cu PostgreSQL |
| `PyJWT` | Creează și verifică tokenurile JWT |
| `bcrypt` | Criptarea parolelor (hash lent, cu salt) |
| `email-validator` | Validează adresele de email la înregistrare |
| `pytest`, `httpx` | Teste automate ale API-ului |

### Raspberry Pi
| Bibliotecă | Rol |
|-----------|-----|
| `requests` | Cererile HTTP către server |
| `adafruit-circuitpython-servokit` | API simplu pentru servomotoare (`kit.servo[i].angle = …`) |
| `adafruit-circuitpython-pca9685` | Driverul plăcii PWM PCA9685 pe I²C |
| `systemd` (`robot-hand.service`) | Pornește programul la boot și îl repornește dacă se oprește |

### Antrenarea ML
| Bibliotecă | Rol |
|-----------|-----|
| `mediapipe` | Extrage punctele mâinii din imagini sau din webcam (aceeași rețea ca în aplicație) |
| `opencv-python` | Webcam, ferestre, citirea imaginilor |
| `pandas`, `numpy` | Lucrul cu CSV-urile și calcul numeric |
| `scikit-learn` | RandomForest (bază de comparație), metrici, matrice de confuzie |
| `tensorflow` / `keras` | Antrenarea rețelelor dense și GRU/LSTM |
| `joblib` | Salvarea modelului RandomForest |

### Infrastructură
| Unealtă | Rol |
|--------|-----|
| Docker + Docker Compose | Pornesc PostgreSQL și serverul cu o singură comandă |
| PostgreSQL 16 | Baza de date relațională |

---

## 6. Scalabilitate

Ideea de bază: **recunoașterea semnelor rulează pe telefon**. Serverul primește
doar texte mici (cam 1 cerere la 10 secunde de la un utilizator activ), niciodată
video. De aceea arhitectura scalează mult mai ușor decât dacă ML-ul ar rula pe
server: 1 milion de utilizatori × 30 de cadre/s ar însemna GPU-uri scumpe.

Estimare de trafic: un utilizator activ face ~0,1 cereri/s. La vârf sunt online
cam 10% dintre utilizatori.

### Stadiul A: acum (1–50 de utilizatori, demo)
- **Cum arată:** un laptop cu Docker Compose (un proces Uvicorn + PostgreSQL), o rețea Wi-Fi locală, un Raspberry Pi, o mână robotică.
- **Încărcare:** < 5 cereri/s. Un singur proces FastAPI duce sute de cereri/s.
- **Limite:**
  - Un singur punct de cădere (laptopul).
  - HTTP fără criptare (doar în rețeaua locală).
  - Tabelele sunt create cu `create_all`, fără migrări.
  - Pi-ul face polling de 2 cereri/s chiar și când nu are nimic de făcut.
  - **Mâna robotică e un singur dispozitiv fizic:** o comandă durează ~5 s, deci maxim ~12 comenzi/minut, iar comenzile se pun la coadă. Hardware-ul nu scalează: la mulți utilizatori, mâna rămâne o funcție de demonstrație sau de laborator.
- **Cost:** 0 € (hardware existent).

### Stadiul B: intermediar (1.000–10.000 de utilizatori)
- **Încărcare:** 10.000 × 10% × 0,1 = **~100 cereri/s la vârf**. Un VM cu 2–4 vCPU și 4–8 Uvicorn workers duce asta.
- **Schimbări și de ce:**
  1. **Cloud** (VM sau container gestionat) în loc de laptop, ca să fie disponibil 24/7.
  2. **HTTPS** cu reverse proxy (Nginx/Caddy + Let's Encrypt), ca tokenurile și parolele să nu circule în clar.
  3. **Gunicorn + mai mulți workers Uvicorn**, ca să folosească toate nucleele CPU.
  4. **PostgreSQL gestionat** (backup automat, point-in-time recovery) și **Alembic** pentru migrări, ca schema să poată fi schimbată fără pierderi de date.
  5. **Cache pentru `/signs`** (lista se schimbă rar): HTTP `ETag` / `Cache-Control`, ca să scadă cererile repetate.
  6. **Rate limiting** pe `/auth/*`, împotriva ghicirii parolelor (brute-force).
  7. **Monitorizare:** Sentry pentru erori, Prometheus + Grafana pentru latență și CPU.
  8. **CI/CD** (GitHub Actions: teste, build, deploy).
  9. **Mâini robotice:** o tabelă `devices`, o cheie pentru fiecare dispozitiv și o coadă pentru fiecare mână. Polling-ul se înlocuiește cu long-polling sau WebSocket.
  10. **Date:** 10.000 de utilizatori × 50 de încercări/zi = 500.000 de rânduri/zi în `practice_sessions` (~180 de milioane pe an). Soluția: partiționare pe lună, păstrarea datelor brute doar 90 de zile și statistici agregate.
  11. **Offline-first** în aplicație: semnele și progresul se salvează local (SQLite/drift), iar scrierile se sincronizează când revine conexiunea.
- **Cost estimat:** ~20–100 €/lună.

### Stadiul C: 1.000.000 de utilizatori
- **Încărcare:** 1.000.000 × 10% × 0,1 = **~10.000 cereri/s la vârf**, iar `practice_sessions` crește cu ~50 de milioane de rânduri pe zi.
- **Schimbări și de ce:**
  1. **API-ul scalat orizontal:** multe containere identice în spatele unui load balancer, cu Kubernetes și autoscaling. Merge pentru că JWT-ul **nu ține stare pe server**, deci orice instanță poate răspunde oricărei cereri.
  2. **Baza de date:** un PostgreSQL principal + **read replicas** pentru citiri, **PgBouncer** pentru pool-ul de conexiuni, partiționare sau sharding după `user_id`.
  3. **Evenimentele (încercările) separate de datele tranzacționale:** API-ul le pune într-o coadă (Kafka / Redis Streams sau Pub/Sub), iar un worker le scrie într-un depozit analitic (ClickHouse / BigQuery). Răspunsul către aplicație nu mai așteaptă scrierea.
  4. **Redis** pentru cache (lista de semne, sesiuni, rate limiting).
  5. **CDN** pentru conținut static: videoclipuri și imagini cu semnele, și **fișierele modelelor ML cu versiune**. Aplicația descarcă un model nou fără o versiune nouă în magazin (OTA).
  6. **Autentificare gestionată** (Keycloak / Auth0 / Cognito): verificarea emailului, resetarea parolei, login cu Google sau Apple, 2FA.
  7. **Mai multe platforme:** pluginul `hand_landmarker` merge doar pe Android, deci e nevoie de MediaPipe pentru iOS și de MediaPipe Tasks Vision (JS/WebAssembly) pentru web.
  8. **Mai multe regiuni**, pentru latență mică și redundanță. Plus GDPR (date în UE, ștergerea contului).
  9. **Mâinile robotice:** un broker **MQTT** (Mosquitto / EMQX) pentru mii de dispozitive, comenzi push în loc de polling, telemetrie.
  10. **Observabilitate:** tracing distribuit (OpenTelemetry), SLO-uri, alerte.
- **Ce rămâne neschimbat:** recunoașterea semnelor, tot pe telefon, cu cost de server zero.
- **Cost estimat:** de ordinul miilor de €/lună. Cel mai mult costă baza de date și stocarea evenimentelor.

| | A: acum | B: 10.000 | C: 1.000.000 |
|---|---|---|---|
| Cereri/s la vârf | < 5 | ~100 | ~10.000 |
| Server API | 1 proces pe laptop | 1 VM, 4–8 workers, HTTPS | N containere, Kubernetes, load balancer, autoscaling |
| Baza de date | PostgreSQL în Docker | PostgreSQL gestionat + backup + Alembic | Primar + replici + PgBouncer + partiționare; evenimentele în ClickHouse/BigQuery |
| Cache | – | ETag pe `/signs` | Redis + CDN |
| ML | Pe telefon, model în APK | Pe telefon | Pe telefon, model OTA de pe CDN cu versiune |
| Robot | 1 Pi, polling HTTP | Mai multe dispozitive, long-polling/WebSocket | MQTT broker |
| Platforme | Android | Android + offline-first | Android, iOS, web |
| Cost / lună | 0 € | 20–100 € | mii de € |

---

## 7. Compromisuri în arhitectura mobilă

| Criteriu | Ce am ales | Alternative și compromis |
|---------|------------|--------------------------|
| **Utilizabilitate (dispozitiv)** | Telefon sau tabletă cu cameră frontală. Tableta e ideală: ecran mare pentru demonstrație, se poate sprijini pe masă | **Smartwatch:** nu, nu are cameră frontală potrivită, iar ecranul e prea mic ca să vezi un semn. Mâinile sunt ocupate să facă semnul. **Desktop/web:** UI-ul merge, recunoașterea încă nu (pluginul e doar pentru Android) |
| **Timp de finalizare** | Flutter: un singur cod pentru toate platformele. Rețeaua rescrisă în Dart, ca să evităm problemele cu pluginul TFLite. FastAPI: puțin cod, documentație automată | Nativ (Kotlin + Swift) ar însemna dublu timp. Pe termen scurt am livrat doar Android. Pe termen lung urmează iOS și offline-first |
| **Portabilitate** | Flutter merge pe Android, iOS, web, Windows, macOS, Linux. **Minim Android 7.0 (API 24)**, cerut de `hand_landmarker`, deci marea majoritate a dispozitivelor Android active | OS-uri mai vechi de Android 7: nu, MediaPipe nu le suportă. Cea mai nouă versiune: OK, `targetSdk` urmează Flutter. iOS: UI-ul merge, recunoașterea ar avea nevoie de un plugin iOS |
| **Complexitate (WebView vs nativ)** | Flutter e compilat nativ și desenează UI-ul singur. Camera și ML-ul la 30 de cadre/s au nevoie de acces nativ | Un WebView/HTML5 ar fi fost mai simplu, dar lent la cameră + ML. Facebook a mizat pe HTML5 până în 2012, apoi a rescris aplicația nativ din cauza performanței. React Native ar fi fost o alternativă |
| **Instalare** | Aplicație dedicată (APK, Google Play) | O aplicație web/PWA nu cere instalare, dar acum nu are recunoaștere. În viitor se poate face cu MediaPipe JS. Un APK cere instalare, dar dă acces complet la cameră și performanță |
| **Performanță / baterie** | Model mic (~6.400 de parametri), MediaPipe pe CPU, o singură mână. Camera e pornită doar pe tabul vizibil. Rețeaua face polling doar cât așteaptă robotul | Pokémon Go ține GPS + cameră + AR + rețea pornite continuu, deci consumă mult. La noi cel mai mult consumă camera + MediaPipe, și doar în timpul exersării. Se poate îmbunătăți cu delegat GPU și cu procesarea doar a unora dintre cadre |
| **Cost** | Doar open-source. Serverul e ieftin pentru că inferența se face pe telefon. Am renunțat la Firebase, care se plătește pe fiecare citire/scriere | ML pe server ar costa GPU-uri. Un BaaS (Firebase) e rapid la început, dar scump și greu de controlat la scară |
| **Mentenanță** | Un cod Dart pentru aplicație, un cod Python pentru server. Teste pytest. `selfTest()` verifică dacă ML-ul din Dart dă aceleași rezultate ca Python | Normalizarea punctelor trebuie ținută identică în Python și în Dart. Un model nou cere acum o versiune nouă a aplicației (în viitor: OTA). Schema bazei de date are nevoie de migrări (Alembic) |
| **Acces la resurse / offline** | Server: conturi, progres, robot. Local: modelele ML (merg offline), tokenul și limba (`shared_preferences`) | Acum lista de semne și progresul cer conexiune. Îmbunătățire: cache local (SQLite) și o coadă de sincronizare. Backup: `pg_dump` sau backup gestionat pe server |
