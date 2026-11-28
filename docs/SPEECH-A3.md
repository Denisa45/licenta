# Hand in Hand — presentation speech (A3 sheet)

Total: about 9 minutes. Text in [brackets] tells you where to point on the sheet.
Follow the block numbers 1 → 5, then the trade-offs (oral only), then the demo.

---

## Opening (~15 s)

Good morning. Our project is **Hand in Hand**, a mobile app for learning Romanian Sign Language. The tablet's camera recognizes the learner's signs, and an optional robotic hand shows how each sign is made. I'll walk you through the architecture block by block.

---

## Block 1 — System overview (~2 min)

[point at the whole block 1]

Our system follows a **distributed client-server architecture**, organized in **three tiers**. It is *distributed* because the components run on different devices — a tablet, a laptop and a Raspberry Pi — and talk over the network. It is *three-tier* because each part has one job.

[point at PRESENTATION, the green tablet]
The **presentation tier** is a **Flutter** app running on an Android tablet.

[point at APPLICATION, FastAPI]
The **application tier** is a **FastAPI** server written in Python. It handles accounts, progress and the business rules.

[point at DATA, PostgreSQL]
The **data tier** is a **PostgreSQL** database. The server and the database both run in **Docker** on a laptop today, and could move to the cloud unchanged.

[point at arrow A]
The app talks to the server over **HTTP**, using **JSON**, and sends a **JWT token** with every request to prove who the user is.

[point at arrow B]
Only the server talks to the database, using **SQL**. The app never touches the database directly.

[point at LOCAL ML inside the tablet]
The most important decision is here: **sign recognition runs on the tablet itself**. The camera, MediaPipe and our neural network all run on the device. Camera images never leave it. This makes recognition work offline, respond instantly, protect the user's privacy, and keep our server cheap — because the server only ever receives a small result, never video.

[point at arrow E and the purple training box]
The model is trained beforehand on a laptop with Keras, exported to a JSON file, and shipped inside the app.

[point at the orange Raspberry Pi box, arrows C and D]
Finally, the **robotic hand is optional**. A Raspberry Pi asks the server every half second whether there is a command for it — because it sits behind a router, the server cannot reach it directly. When there is one, it moves five servos. The app works fully without it.

---

## Block 2 — Mobile app (~1.5 min)

[point at the five layers]
Inside the app, the code is organized in **five layers**, and each layer only uses the one below it. **Screens** show the interface. They call **services** — for accounts, progress and the robot. Services call a single **ApiClient**, the only class that talks to the network. Below that is the **ML** code, and at the bottom the **platform** plugins for the camera and local storage.

Because screens never call the network directly, when we replaced Firebase with our own backend we only rewrote the services — the screens barely changed.

[point at RECOGNITION, steps 1 to 5]
Recognition happens in five steps, all on the tablet:
1. the **camera** streams frames;
2. **MediaPipe** finds **21 points** on the hand;
3. we **normalize** them into **63 numbers** — wrist at the origin, scaled by palm size — so the result doesn't depend on distance from the camera;
4. our **neural network**, written directly in Dart, gives a probability for each sign;
5. if the right sign stays above **80 percent for one second**, it counts as recognized.

[point at "Then: POST /sessions"]
Only then does the app send one request to the server, with the sign and the confidence.

---

## Block 3 — Backend (~1.5 min)

[point at the chain Uvicorn → SQLAlchemy]
Every request follows the same path on the server. **Uvicorn** receives the connection. **FastAPI** finds the right function for the URL. **Pydantic** validates the data — wrong values are rejected before they reach the database. The **JWT check** verifies the token and finds out who the user is. And **SQLAlchemy** turns our Python objects into SQL for PostgreSQL.

[point at URLS]
These are the main URLs: login, reading the lessons and progress, saving an attempt, completing a lesson, and sending a command to the robot. FastAPI also generates live documentation of all of them at `/docs`.

[point at SECURITY]
Passwords are stored only as **bcrypt hashes** — one-way, salted and deliberately slow, so not even we can read them. Login returns a **signed JWT** valid for 30 days. The server always takes the user's identity **from the token**, never from the request, so each user can only see their own data.

[point at TABLES]
The database has six tables. The core relationship is that a **user has progress on many signs**, enforced with foreign keys and a unique constraint.

---

## Block 4 — Scaling (~1.5 min)

[point at NOW]
**Today**, everything runs on one laptop with Docker, and the tablet connects over a USB cable. It handles our load easily — fewer than five requests per second — but the laptop is a single point of failure, and there is only one physical robot hand.

[point at 10K]
At **ten thousand users**, about a hundred requests per second at peak, we move to a cloud server with **HTTPS**, run several server processes to use all CPU cores, switch to a managed database with automatic backups, and add an offline cache in the app.

[point at 1M]
At **one million users**, about ten thousand requests per second, we put a **load balancer** in front of many copies of the API on Kubernetes. This works because our API is **stateless** — the user's identity travels in the token, so any copy can answer any request. The database gets **replicas** and sharding, practice attempts go through a **queue** into an analytics store, and we add caching and a CDN. We'd also support iOS and the web, and use MQTT for many robots.

[point at "recognition stays on the device at every stage"]
What never changes is that recognition stays on the device. That's why scaling stays affordable: the server only handles small text requests.

---

## Block 5 — Libraries (~1 min)

[point at TABLET]
On the tablet: **flutter** for the interface, **camera** for the frames, **hand_landmarker** for MediaPipe, **http** for the requests, and **shared_preferences** to keep the token and language.

[point at SERVER]
On the server: **uvicorn** runs the server, **fastapi** defines the routes, **pydantic** validates data, **SQLAlchemy** and **psycopg** talk to PostgreSQL, and **PyJWT** and **bcrypt** handle security.

[point at RASPBERRY PI and ML TRAINING]
The Pi uses **requests** to poll the server and **servokit** to drive the servos. For training we used **MediaPipe** and **OpenCV** to collect data, **TensorFlow** to train, and **scikit-learn** to evaluate.

---

## Trade-offs — oral only (~40 s)

A few trade-offs we made:
- **Usability:** we target tablets, not smartwatches — you need a camera, a screen big enough to see the sign, and both hands free.
- **Finalization time:** Flutter gave us one codebase instead of two native apps.
- **Portability:** we support Android 7 up to 16; the lower limit comes from MediaPipe, and iOS would need another plugin.
- **Complexity and installation:** a native, installed app instead of a web view or web app, because real-time camera ML needs native speed.
- **Performance and cost:** a small model on the device saves battery, server cost and works offline.
- **Maintenance and resources:** the price is two languages, Dart and Python, and the app still needs a connection to save progress.

---

## Closing and demo (~1 min)

To sum up: a three-tier, client-server system with machine learning at the edge, which keeps it fast, private and cheap to scale.

Let me show you quickly. [on the tablet] I log in, open a lesson, and make the sign. [point at the camera] Recognition happens right here on the tablet. [on the laptop, pgAdmin or the server log] And here is the one row that reached the server: the sign and the confidence — no image.

Thank you. We're happy to take questions — and our agent can show you any part of the code.
