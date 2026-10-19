import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

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
  /// 'description_en' from Firestore, or one made from robot_pose when missing.
  String get localDescription =>
      appLang.value == AppLang.en ? descriptionEn : description;

  String get howTo => localDescription.isNotEmpty
      ? localDescription
      : tr(
          'Ridică $raisedFingersText; celelalte degete rămân îndoite.',
          'Raise the $raisedFingersText; keep the other fingers bent.',
        );

  factory Sign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final pose = (data['robot_pose'] as Map<String, dynamic>? ?? {});
    return Sign(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString().trim(),
      descriptionEn: (data['description_en'] ?? '').toString().trim(),
      unit: (data['unit'] ?? '').toString(),
      difficulty: (data['difficulty'] ?? 1) as int,
      order: (data['order'] ?? 0) as int,
      verified: (data['verified'] ?? false) as bool,
      robotPose: pose.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}
