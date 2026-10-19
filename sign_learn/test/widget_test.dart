import 'package:flutter_test/flutter_test.dart';

import 'package:sign_learn/sign_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Dart network gives the same output as Python (selfTest)', () async {
    final classifier = await SignClassifier.load();
    expect(classifier.labels, ['1', '2', '3', '4', '5']);
    final diff = classifier.selfTest();
    expect(diff, isNotNull);
    expect(diff!, lessThan(1e-4));
  });

  test('normalize puts the wrist at 0 and landmark 9 at distance 1', () {
    final points = [
      for (var i = 0; i < 21; i++) (0.5 + i * 0.01, 0.8 - i * 0.02, 0.0),
    ];
    final f = SignClassifier.normalize(points);
    expect(f.length, 63);
    expect(f.sublist(0, 3), [0.0, 0.0, 0.0]);
    final (x, y, z) = (f[27], f[28], f[29]);
    expect(x * x + y * y + z * z, closeTo(1, 1e-9));
  });
}
