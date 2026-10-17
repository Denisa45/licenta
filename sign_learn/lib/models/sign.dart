import 'package:cloud_firestore/cloud_firestore.dart';

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
