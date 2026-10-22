// lib/services/robot_service.dart
//
// Sends a sign to the robotic hand through Firestore:
//   robot_commands/{auto}  {sign_id, uid, status: 'pending', created_at}
// The Raspberry Pi (hw/command_listener.py) takes the command, moves the hand
// and sets status to 'processing', then 'completed' or 'error'.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RobotService {
  RobotService._();
  static final instance = RobotService._();

  final _db = FirebaseFirestore.instance;

  /// Creates the command and returns the stream of its status.
  Future<Stream<String>> showSign(String signId) async {
    final ref = await _db.collection('robot_commands').add({
      'sign_id': signId,
      'uid': FirebaseAuth.instance.currentUser?.uid,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.snapshots().map(
      (snap) => (snap.data()?['status'] ?? 'pending').toString(),
    );
  }
}
