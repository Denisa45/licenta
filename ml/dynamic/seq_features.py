"""
Shared code for the dynamic (moving) signs: how one recording becomes the
input of the network. The Dart app (lib/dynamic_sign_classifier.dart) repeats
EXACTLY these steps, so change both together.

A recording is a list of frames, each with a time in seconds and the 21 hand
landmarks in pixel units of the frame (x * width, y * height, z * width), so x
and y have the real proportions of the image.

Steps:
  1. resample()   -> T frames evenly spaced in time (the sign can be done
                     faster or slower, and the webcam and tablet run at
                     different frame rates)
  2. features()   -> per frame: the hand shape (63 numbers, normalized like the
                     static signs: wrist at 0, wrist->middle-finger base = 1)
                     + where the wrist moved since the first frame (dx, dy),
                     in hand lengths, so the motion does not depend on how far
                     the hand is from the camera.
"""
import numpy as np

T = 30                # frames per sequence given to the network
DURATION = 2.0        # seconds recorded for one sign (record_sequences.py and the app)
MIN_HAND_FRAMES = 0.6 # fraction of frames that must show the hand
N_FEATURES = 63 + 2


def resample(times, points, n=T):
    """times: (k,) seconds, points: (k, 21, 3). Returns (n, 21, 3), the points at
    n moments evenly spaced between the first and the last frame (linear
    interpolation between the two nearest frames)."""
    times = np.asarray(times, dtype=np.float64)
    points = np.asarray(points, dtype=np.float64)
    if len(times) == 1:
        return np.repeat(points, n, axis=0)
    targets = np.linspace(times[0], times[-1], n)
    flat = points.reshape(len(times), -1)
    out = np.empty((n, flat.shape[1]))
    for j in range(flat.shape[1]):
        out[:, j] = np.interp(targets, times, flat[:, j])
    return out.reshape(n, 21, 3)


def hand_scale(p):
    """Distance wrist (0) -> middle-finger base (9), the static normalize()."""
    s = np.linalg.norm(p[9] - p[0])
    return s if s > 0 else 1.0


def features(seq):
    """seq: (T, 21, 3) pixel-unit landmarks -> (T, 65) float32."""
    seq = np.asarray(seq, dtype=np.float64)
    out = np.empty((len(seq), N_FEATURES), dtype=np.float32)
    origin = seq[0, 0, :2]
    ref = hand_scale(seq[0])
    for t, p in enumerate(seq):
        shape = (p - p[0]) / hand_scale(p)
        out[t, :63] = shape.reshape(-1)
        out[t, 63:] = (p[0, :2] - origin) / ref
    return out


def mirror(feats):
    """Left/right mirror of a (..., 65) feature array: every x is negated
    (shape x columns 0, 3, ..., 60 and the wrist dx column 63)."""
    m = np.array(feats, copy=True)
    m[..., 0:63:3] *= -1
    m[..., 63] *= -1
    return m
