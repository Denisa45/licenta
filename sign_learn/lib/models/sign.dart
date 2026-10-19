import 'package:cloud_firestore/cloud_firestore.dart';

/// Finger keys used in robot_pose, from thumb to pinky.
const kFingers = ['thumb', 'index', 'middle', 'ring', 'pinky'];

/// Romanian names for the robot_pose finger keys.
const kFingerNames = {
  'thumb': 'degetul mare',
  'index': 'arătătorul',
  'middle': 'mijlociul',
  'ring': 'inelarul',
  'pinky': 'degetul mic',
};

class Sign {
  final String id;
  final String name;
  final String description;
  final String unit;
  final int difficulty;
  final int order;
  final bool verified;
  final Map<String, int> robotPose;

  const Sign({
    required this.id,
    required this.name,
    required this.description,
    required this.unit,
    required this.difficulty,
    required this.order,
    required this.verified,
    required this.robotPose,
  });

  /// Fingers that are up (value 1 in robot_pose), from thumb to pinky.
  List<String> get raisedFingers =>
      [for (final f in kFingers) if ((robotPose[f] ?? 0) == 1) f];

  /// Raised fingers in Romanian, e.g. "arătătorul și mijlociul".
  String get raisedFingersText {
    final names = [for (final f in raisedFingers) kFingerNames[f]!];
    if (names.length < 2) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} și ${names.last}';
  }

  /// The description from Firestore, or one made from robot_pose when it is empty.
  String get howTo => description.isNotEmpty
      ? description
      : 'Ridică $raisedFingersText; celelalte degete rămân îndoite.';

  factory Sign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final pose = (data['robot_pose'] as Map<String, dynamic>? ?? {});
    return Sign(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      description: (data['description'] ?? '').toString().trim(),
      unit: (data['unit'] ?? '').toString(),
      difficulty: (data['difficulty'] ?? 1) as int,
      order: (data['order'] ?? 0) as int,
      verified: (data['verified'] ?? false) as bool,
      robotPose: pose.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}
