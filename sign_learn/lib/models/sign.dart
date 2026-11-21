import '../l10n.dart';

/// Finger keys used in robot_pose, from thumb to pinky.
const kFingers = ['thumb', 'index', 'middle', 'ring', 'pinky'];

/// Finger names (Romanian / English) for the robot_pose finger keys.
const _fingerNames = {
  'thumb': ('degetul mare', 'thumb'),
  'index': ('arătătorul', 'index finger'),
  'middle': ('mijlociul', 'middle finger'),
  'ring': ('inelarul', 'ring finger'),
  'pinky': ('degetul mic', 'little finger'),
};

/// Name of a robot_pose finger key in the current language.
String fingerName(String finger) {
  final (ro, en) = _fingerNames[finger]!;
  return tr(ro, en);
}

class Sign {
  final String id;
  final String name;
  final String description;
  final String descriptionEn;
  final String unit;
  final int difficulty;
  final int order;
  final bool verified;
  final Map<String, int> robotPose;

  /// Model label the camera must see for this sign: 'shape' from the server,
  /// or the sign's own name. V uses the shape of 2, B of 4, D of 1.
  final String shape;

  /// For a word lesson, the ids of its letter signs in order (DA: ['D', 'A']).
  /// Empty for a single sign.
  final List<String> letters;

  /// True for a sign with movement ('motion: true' on the server): it is
  /// checked by the sequence model (DynamicSignCamera), not by a held shape.
  final bool motion;

  const Sign({
    required this.id,
    required this.name,
    required this.description,
    this.descriptionEn = '',
    required this.unit,
    required this.difficulty,
    required this.order,
    required this.verified,
    required this.robotPose,
    required this.shape,
    this.letters = const [],
    this.motion = false,
  });

  bool get isWord => letters.isNotEmpty;

  /// 'Semnul' or 'Cuvântul', for titles such as "Semnul A" and "Cuvântul DA".
  String get kind => isWord ? tr('Cuvântul', 'Word') : tr('Semnul', 'Sign');

  /// Fingers that are up (value 1 in robot_pose), from thumb to pinky.
  List<String> get raisedFingers => [
    for (final f in kFingers)
      if ((robotPose[f] ?? 0) == 1) f,
  ];

  /// Raised fingers as text, e.g. "arătătorul și mijlociul".
  String get raisedFingersText {
    final names = [for (final f in raisedFingers) fingerName(f)];
    if (names.length < 2) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} '
        '${tr('și', 'and')} ${names.last}';
  }

  /// Description in the current language: 'description' (Romanian) or
  /// 'description_en' from the server, or one made from robot_pose when missing.
  String get localDescription =>
      appLang.value == AppLang.en ? descriptionEn : description;

  String get howTo => localDescription.isNotEmpty
      ? localDescription
      : isWord
      ? tr(
          'Arată literele pe rând: ${letters.join(', ')}.',
          'Show the letters one after another: ${letters.join(', ')}.',
        )
      : tr(
          'Ridică $raisedFingersText; celelalte degete rămân îndoite.',
          'Raise the $raisedFingersText; keep the other fingers bent.',
        );

  /// One sign from GET /signs (same fields as the old Firestore 'signs').
  factory Sign.fromJson(Map<String, dynamic> data) {
    final pose = (data['robot_pose'] as Map<String, dynamic>? ?? {});
    return Sign(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString().trim(),
      descriptionEn: (data['description_en'] ?? '').toString().trim(),
      unit: (data['unit'] ?? '').toString(),
      difficulty: (data['difficulty'] as num?)?.toInt() ?? 1,
      order: (data['order'] as num?)?.toInt() ?? 0,
      verified: (data['verified'] ?? false) as bool,
      robotPose: pose.map((k, v) => MapEntry(k, (v as num).toInt())),
      // An empty or missing 'shape' means the sign's own name (A is seen as A).
      shape: switch ((data['shape'] ?? '').toString()) {
        '' => (data['name'] ?? '').toString(),
        final shape => shape,
      },
      letters: [for (final l in data['letters'] as List? ?? []) l.toString()],
      motion: (data['motion'] ?? false) as bool,
    );
  }
}
