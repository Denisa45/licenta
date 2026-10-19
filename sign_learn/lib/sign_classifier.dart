// lib/sign_classifier.dart
//
// Runs the small network exported by export_weights.py (63 inputs -> 5 signs)
// in plain Dart, so no TFLite plugin is needed.
//
// Needs in pubspec.yaml:
//   flutter:
//     assets:
//       - assets/sign_model.json

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

class SignPrediction {
  final String label;
  final double confidence;
  final List<double> probabilities;
  const SignPrediction(this.label, this.confidence, this.probabilities);

  @override
  String toString() =>
      'sign $label (${(confidence * 100).toStringAsFixed(0)}%)';
}

class _Dense {
  final List<List<double>> w; // [input][output]
  final List<double> b;
  final String activation;
  _Dense(this.w, this.b, this.activation);
}

class SignClassifier {
  final List<String> labels;
  final List<_Dense> _layers;
  final List<double>? _testInput;
  final List<double>? _testOutput;

  SignClassifier._(
    this.labels,
    this._layers,
    this._testInput,
    this._testOutput,
  );

  static Future<SignClassifier> load([
    String asset = 'assets/sign_model.json',
  ]) async {
    final data =
        jsonDecode(await rootBundle.loadString(asset)) as Map<String, dynamic>;

    List<double> doubles(dynamic list) =>
        (list as List).map((v) => (v as num).toDouble()).toList();

    final layers = (data['layers'] as List).map((l) {
      final w = (l['w'] as List).map((row) => doubles(row)).toList();
      return _Dense(w, doubles(l['b']), l['activation'] as String);
    }).toList();

    final test = data['test'] as Map<String, dynamic>?;
    return SignClassifier._(
      (data['labels'] as List).cast<String>(),
      layers,
      test == null ? null : doubles(test['input']),
      test == null ? null : doubles(test['output']),
    );
  }

  /// Same steps as normalize() in extract_landmarks.py / record_takes.py:
  /// wrist at the origin, scaled so wrist -> middle-finger base (index 9) = 1.
  /// [points] must be the 21 MediaPipe landmarks in order, as (x, y, z).
  /// Returns 63 numbers: x0, y0, z0, x1, y1, z1, ...
  static List<double> normalize(List<(double, double, double)> points) {
    assert(points.length == 21, 'expected 21 landmarks');
    final (wx, wy, wz) = points[0];
    final shifted = [for (final (x, y, z) in points) (x - wx, y - wy, z - wz)];
    final (mx, my, mz) = shifted[9];
    var scale = math.sqrt(mx * mx + my * my + mz * mz);
    if (scale == 0) scale = 1.0;
    return [
      for (final (x, y, z) in shifted) ...[x / scale, y / scale, z / scale],
    ];
  }

  /// Raw network output for 63 normalized features.
  List<double> probabilities(List<double> input) {
    var x = input;
    for (final layer in _layers) {
      final out = List<double>.from(layer.b);
      for (var i = 0; i < x.length; i++) {
        final xi = x[i];
        final row = layer.w[i];
        for (var j = 0; j < out.length; j++) {
          out[j] += xi * row[j];
        }
      }
      switch (layer.activation) {
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
      x = out;
    }
    return x;
  }

  /// Convenience: landmarks in, best sign out.
  SignPrediction classify(List<(double, double, double)> landmarks) {
    final p = probabilities(normalize(landmarks));
    var best = 0;
    for (var i = 1; i < p.length; i++) {
      if (p[i] > p[best]) best = i;
    }
    return SignPrediction(labels[best], p[best], p);
  }

  /// Checks the Dart maths against the sample exported from Python.
  /// Returns the largest difference (should be about 0.0001 or less),
  /// or null if the JSON has no test sample.
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
