// lib/dynamic_sign_classifier.dart
//
// Runs the dynamic-sign network exported by ml/dynamic/export_seq_weights.py
// (a GRU or LSTM over 30 frames, then Dense layers) in plain Dart, like
// SignClassifier does for the static signs.
//
// The steps from landmarks to network input repeat ml/dynamic/seq_features.py
// exactly: resample() to [frames] moments evenly spaced in time, then
// features() = hand shape (63, normalized like the static signs) + wrist motion
// since the first frame, in hand lengths (2).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'sign_classifier.dart';

typedef Point3 = (double, double, double);

/// One recorded camera frame: seconds since the start, 21 landmarks in pixel
/// proportions (x * width, y * height, z * width), as SignCamera.onHand gives.
typedef TimedHand = (double, List<Point3>);

abstract class _Layer {
  List<double> run(List<List<double>> sequence);
}

double _sigmoid(double x) => 1 / (1 + math.exp(-x));
double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// out[j] = bias[j] + sum_i x[i] * w[i][j]
List<double> _matVec(List<double> x, List<List<double>> w, List<double> bias) {
  final out = List<double>.from(bias);
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    if (xi == 0) continue;
    final row = w[i];
    for (var j = 0; j < out.length; j++) {
      out[j] += xi * row[j];
    }
  }
  return out;
}

/// Keras GRU with reset_after=True (the default): gates in the order z, r, h.
class _Gru implements _Layer {
  final int units;
  final List<List<double>> kernel, recurrent;
  final List<double> biasIn, biasRec;
  _Gru(this.units, this.kernel, this.recurrent, this.biasIn, this.biasRec);

  @override
  List<double> run(List<List<double>> sequence) {
    final u = units;
    var h = List<double>.filled(u, 0);
    for (final x in sequence) {
      final mx = _matVec(x, kernel, biasIn);
      final mh = _matVec(h, recurrent, biasRec);
      final next = List<double>.filled(u, 0);
      for (var j = 0; j < u; j++) {
        final z = _sigmoid(mx[j] + mh[j]);
        final r = _sigmoid(mx[u + j] + mh[u + j]);
        final cand = _tanh(mx[2 * u + j] + r * mh[2 * u + j]);
        next[j] = z * h[j] + (1 - z) * cand;
      }
      h = next;
    }
    return h;
  }
}

/// Keras LSTM: gates in the order i, f, c, o.
class _Lstm implements _Layer {
  final int units;
  final List<List<double>> kernel, recurrent;
  final List<double> bias;
  _Lstm(this.units, this.kernel, this.recurrent, this.bias);

  @override
  List<double> run(List<List<double>> sequence) {
    final u = units;
    var h = List<double>.filled(u, 0);
    final c = List<double>.filled(u, 0);
    for (final x in sequence) {
      final g = _matVec(x, kernel, bias);
      final gh = _matVec(h, recurrent, List<double>.filled(4 * u, 0));
      final next = List<double>.filled(u, 0);
      for (var j = 0; j < u; j++) {
        final i = _sigmoid(g[j] + gh[j]);
        final f = _sigmoid(g[u + j] + gh[u + j]);
        final cand = _tanh(g[2 * u + j] + gh[2 * u + j]);
        final o = _sigmoid(g[3 * u + j] + gh[3 * u + j]);
        c[j] = f * c[j] + i * cand;
        next[j] = o * _tanh(c[j]);
      }
      h = next;
    }
    return h;
  }
}

class _Dense {
  final List<List<double>> w;
  final List<double> b;
  final String activation;
  _Dense(this.w, this.b, this.activation);

  List<double> run(List<double> x) {
    final out = _matVec(x, w, b);
    switch (activation) {
      case 'relu':
        for (var j = 0; j < out.length; j++) {
          if (out[j] < 0) out[j] = 0;
        }
      case 'softmax':
        final m = out.reduce(math.max);
        var sum = 0.0;
        for (var j = 0; j < out.length; j++) {
          out[j] = math.exp(out[j] - m);
          sum += out[j];
        }
        for (var j = 0; j < out.length; j++) {
          out[j] /= sum;
        }
      default:
        break; // linear
    }
    return out;
  }
}

class DynamicSignClassifier {
  final List<String> labels;

  /// Frames given to the network (T in seq_features.py).
  final int frames;

  /// Seconds recorded for one sign (DURATION in seq_features.py).
  final Duration duration;

  final _Layer _recurrent;
  final List<_Dense> _dense;
  final List<List<double>>? _testInput;
  final List<double>? _testOutput;

  DynamicSignClassifier._(
    this.labels,
    this.frames,
    this.duration,
    this._recurrent,
    this._dense,
    this._testInput,
    this._testOutput,
  );

  /// Null when the app has no dynamic model yet (assets/seq_model.json is
  /// made by export_seq_weights.py after recording and training).
  static Future<DynamicSignClassifier?> load([
    String asset = 'assets/seq_model.json',
  ]) async {
    final String text;
    try {
      text = await rootBundle.loadString(asset);
    } catch (_) {
      return null;
    }
    return fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  static DynamicSignClassifier fromJson(Map<String, dynamic> data) {
    List<double> doubles(dynamic list) =>
        (list as List).map((v) => (v as num).toDouble()).toList();
    List<List<double>> matrix(dynamic rows) =>
        (rows as List).map(doubles).toList();

    _Layer? recurrent;
    final dense = <_Dense>[];
    for (final l in data['layers'] as List) {
      switch (l['type']) {
        case 'gru':
          recurrent = _Gru(
            l['units'] as int,
            matrix(l['kernel']),
            matrix(l['recurrent']),
            doubles(l['bias_in']),
            doubles(l['bias_rec']),
          );
        case 'lstm':
          recurrent = _Lstm(
            l['units'] as int,
            matrix(l['kernel']),
            matrix(l['recurrent']),
            doubles(l['bias']),
          );
        case 'dense':
          dense.add(
            _Dense(matrix(l['w']), doubles(l['b']), l['activation'] as String),
          );
      }
    }
    if (recurrent == null) {
      throw const FormatException('seq_model.json has no GRU/LSTM layer');
    }
    final test = data['test'] as Map<String, dynamic>?;
    return DynamicSignClassifier._(
      (data['labels'] as List).cast<String>(),
      data['frames'] as int,
      Duration(milliseconds: ((data['duration'] as num) * 1000).round()),
      recurrent,
      dense,
      test == null ? null : matrix(test['input']),
      test == null ? null : doubles(test['output']),
    );
  }

  /// [n] frames evenly spaced in time between the first and the last
  /// recorded frame, by linear interpolation (seq_features.resample).
  static List<List<Point3>> resample(List<TimedHand> recording, int n) {
    if (recording.length == 1) {
      return List.filled(n, recording.first.$2);
    }
    final t0 = recording.first.$1;
    final t1 = recording.last.$1;
    final out = <List<Point3>>[];
    var k = 0;
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? t0 : t0 + (t1 - t0) * i / (n - 1);
      while (k < recording.length - 2 && recording[k + 1].$1 < t) {
        k++;
      }
      final (ta, a) = recording[k];
      final (tb, b) = recording[k + 1];
      var f = tb > ta ? (t - ta) / (tb - ta) : 0.0;
      f = f.clamp(0.0, 1.0);
      out.add([
        for (var j = 0; j < 21; j++)
          (
            a[j].$1 + (b[j].$1 - a[j].$1) * f,
            a[j].$2 + (b[j].$2 - a[j].$2) * f,
            a[j].$3 + (b[j].$3 - a[j].$3) * f,
          ),
      ]);
    }
    return out;
  }

  static double _handScale(List<Point3> p) {
    final dx = p[9].$1 - p[0].$1;
    final dy = p[9].$2 - p[0].$2;
    final dz = p[9].$3 - p[0].$3;
    final s = math.sqrt(dx * dx + dy * dy + dz * dz);
    return s == 0 ? 1.0 : s;
  }

  /// Per frame: 63 hand-shape numbers + wrist (dx, dy) since the first frame,
  /// in hand lengths of the first frame (seq_features.features).
  static List<List<double>> features(List<List<Point3>> seq) {
    final (ox, oy, _) = seq.first[0];
    final ref = _handScale(seq.first);
    return [
      for (final p in seq)
        [
          ...SignClassifier.normalize(p),
          (p[0].$1 - ox) / ref,
          (p[0].$2 - oy) / ref,
        ],
    ];
  }

  List<double> probabilities(List<List<double>> input) {
    var x = _recurrent.run(input);
    for (final d in _dense) {
      x = d.run(x);
    }
    return x;
  }

  /// A whole recording in, best sign out.
  SignPrediction classify(List<TimedHand> recording) {
    final p = probabilities(features(resample(recording, frames)));
    var best = 0;
    for (var i = 1; i < p.length; i++) {
      if (p[i] > p[best]) best = i;
    }
    return SignPrediction(labels[best], p[best], p);
  }

  /// Largest difference between Dart and Keras on the exported test sequence
  /// (should be about 0.0001 or less), or null without a test sample.
  double? selfTest() {
    final input = _testInput;
    final expected = _testOutput;
    if (input == null || expected == null) return null;
    final got = probabilities(input);
    var maxDiff = 0.0;
    for (var i = 0; i < expected.length; i++) {
      maxDiff = math.max(maxDiff, (got[i] - expected[i]).abs());
    }
    return maxDiff;
  }
}
