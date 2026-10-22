"""Controlul mâinii robotice: cinci degete, câte un servo pe PCA9685."""
import time

from adafruit_servokit import ServoKit

# deget -> canal pe PCA9685
FINGERS = {"police": 0, "aratator": 1, "mijlociu": 2, "inelar": 4, "mic": 5}
OPEN, CLOSED = 150, 0     # 150 = deget întins, 0 = deget îndoit

kit = ServoKit(channels=16)
for ch in FINGERS.values():
    kit.servo[ch].set_pulse_width_range(600, 2400)

# ultimul unghi comandat pe fiecare canal; citirea înapoi din PCA9685
# se rotunjește (ex. -0.3 în loc de 0) și iese din interval
_current = {}


def move(targets, step=5, delay=0.02):
    """Mută gradual mai multe canale, fiecare spre unghiul lui: {canal: unghi}."""
    start = {ch: _current.get(ch, OPEN) for ch in targets}
    n = max(1, int(max(abs(targets[ch] - start[ch]) for ch in targets) / step))
    for k in range(1, n + 1):
        for ch, a in start.items():
            angle = a + (targets[ch] - a) * k / n
            kit.servo[ch].angle = angle
            _current[ch] = angle
        time.sleep(delay)


def set_fingers(open_fingers):
    """Întinde degetele numite și le îndoaie pe celelalte."""
    move({ch: OPEN if name in open_fingers else CLOSED for name, ch in FINGERS.items()})


def release():
    """Oprește semnalul pe toate canalele: servourile rămân libere."""
    for ch in FINGERS.values():
        kit.servo[ch].angle = None
    _current.clear()
