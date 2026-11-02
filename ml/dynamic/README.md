# Semne dinamice (cu mișcare)

Extensia principală: semne recunoscute dintr-o **secvență de cadre**, nu dintr-o
singură poziție. Un GRU (sau LSTM) pe secvențe de landmark-uri MediaPipe,
comparat cu o metodă fără antrenare, 1-NN cu DTW.

## Pașii

Din folderul `ml/dynamic`:

| Pas | Comandă | Mediu |
|---|---|---|
| 1. Alege semnele | editează `SIGNS` în `record_sequences.py` (10-15 semne) | |
| 2. Înregistrează | `python record_sequences.py` | `.venv-record` (mediapipe, cv2) |
| 3. Antrenează + evaluează | `python train_seq.py` (și `--cell lstm` pentru comparație) | `.venv` (tensorflow) |
| 4. Baseline DTW | `python dtw_baseline.py` | `.venv` |
| 5. Modelul final | `python train_seq.py --final` | `.venv` |
| 6. În aplicație | `python export_seq_weights.py` → `sign_learn/assets/seq_model.json` | `.venv` |
| 7. Firestore | pentru fiecare semn dinamic: `motion: true` și `shape: "<eticheta din SIGNS>"` | |

Rapoartele (acuratețe, matrice de confuzie) se salvează în
`ml/data/dynamic/seq_report_gru.txt`, `seq_report_lstm.txt`, `seq_report_dtw.txt`.

## Înregistrarea

- `SPACE` → numărătoare 3-2-1 → **2 secunde** de înregistrare. Semnul se face
  complet în fereastra de 2 s, pornind din poziția de repaus.
- `n` / `p` schimbă semnul, `x` respinge ultima secvență (greșită).
- Ținta: **30+ secvențe pe semn, în cel puțin 2 sesiuni** (zile / lumină /
  haine diferite). Ultima sesiune a fiecărui semn e setul de test, ca la
  semnele statice (ultimul „take”).
- Se salvează coordonatele în **pixeli**, nenormalizate: dacă schimbăm
  feature-urile mai târziu, nu trebuie reînregistrat nimic.

## Ce primește rețeaua (`seq_features.py`)

1. **Reeșantionare** la `T = 30` cadre egal distanțate în timp (interpolare
   liniară): webcam-ul și tableta au rate de cadre diferite, iar semnul poate fi
   făcut mai repede sau mai încet.
2. **65 de valori pe cadru**:
   - forma mâinii: cele 63 de valori normalizate ca la semnele statice
     (încheietura în origine, încheietură → baza degetului mijlociu = 1);
   - mișcarea: deplasarea încheieturii (dx, dy) față de primul cadru, în
     „lungimi de palmă”, ca să nu depindă de distanța față de cameră.

Aplicația (`lib/dynamic_sign_classifier.dart`) repetă exact acești pași și
rulează GRU/LSTM-ul în Dart, fără plugin TFLite. `export_seq_weights.py` pune în
JSON și o secvență de test, verificată de `DynamicSignClassifier.selfTest()`.

## Augmentare la antrenare

La fiecare rundă se generează variante noi ale fiecărei secvențe: oglindire
(cealaltă mână), viteză și poziție în fereastră (85-100% din înregistrare),
rotație ±12° și scalare ±15% a traiectoriei, zgomot mic pe landmark-uri.

## În aplicație

Un semn cu `motion: true` în Firestore se verifică în lecție și la Exersare cu
`DynamicSignCamera`: butonul Start → 3-2-1 → 2 s de înregistrare → rezultat
(„Corect!” dacă eticheta e cea a lecției cu încredere ≥ 70%). Până există
`assets/seq_model.json`, ecranul spune că modelul nu e încă în aplicație.

## Limitări (de menționat în lucrare)

- O singură mână (MediaPipe Hands cu `numHands: 1`); semnele cu două mâini
  ar cere al doilea set de landmark-uri și poziția mâinilor față de corp
  (MediaPipe Holistic / Pose).
- Poziția e relativă la începutul semnului, nu la corp: semnele care diferă
  doar prin locul unde se fac (la frunte vs. la piept) nu pot fi deosebite.
- Fereastră fixă de 2 s, declanșată cu Start, nu recunoaștere continuă.
