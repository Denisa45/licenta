// lib/services/progress_service.dart
//
// Reads and writes the learner's progress in Firestore:
//   progress/{uid}_{signId}   one document per sign (lesson)
//   practice_sessions/{auto}  one document per camera attempt
//
// Writes never read first: the security rules only allow reading documents that
// already exist and belong to the user, so set(..., merge: true) is used instead.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/sign.dart';

class SignProgress {
  final String signId;
  final String status; // 'in_progress' or 'completed'
  final int attempts;
  final double bestConfidence;
  final int quizScore;
  final int quizTotal;
  final DateTime? completedAt;

  const SignProgress({
    required this.signId,
    required this.status,
    required this.attempts,
    required this.bestConfidence,
    required this.quizScore,
    required this.quizTotal,
    this.completedAt,
  });

  bool get completed => status == 'completed';

  factory SignProgress.fromMap(Map<String, dynamic> d) => SignProgress(
        signId: (d['sign_id'] ?? '').toString(),
        status: (d['status'] ?? 'in_progress').toString(),
        attempts: (d['attempts'] as num?)?.toInt() ?? 0,
        bestConfidence: (d['best_confidence'] as num?)?.toDouble() ?? 0,
        quizScore: (d['quiz_score'] as num?)?.toInt() ?? 0,
        quizTotal: (d['quiz_total'] as num?)?.toInt() ?? 0,
        completedAt: (d['completed_at'] as Timestamp?)?.toDate(),
      );
}

class ProgressService {
  ProgressService._();
  static final instance = ProgressService._();

  final _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String signId) =>
      _db.collection('progress').doc('${uid}_$signId');

  /// All progress documents of the signed-in user, keyed by sign id.
  Stream<Map<String, SignProgress>> watch() {
    final uid = _uid;
    if (uid == null) return Stream.value(const {});
    return _db
        .collection('progress')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => {
              for (final d in snap.docs)
                (d.data()['sign_id'] ?? '').toString():
                    SignProgress.fromMap(d.data()),
            });
  }

  /// Saves one camera attempt and counts it on the lesson.
  /// [step] is 'lesson' or 'practice'; [source] is where the data came from
  /// ('camera' or 'debug_skip').
  Future<void> logSession({
    required Sign target,
    required String predicted,
    required double confidence,
    required bool success,
    required String step,
    String source = 'camera',
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.collection('practice_sessions').add({
      'uid': uid,
      'target_sign': target.id,
      'predicted_sign': predicted,
      'confidence': confidence,
      'success': success,
      'step': step,
      'source': source,
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (step == 'lesson') {
      await _doc(uid, target.id).set({
        'uid': uid,
        'sign_id': target.id,
        'unit': target.unit,
        'attempts': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Marks the lesson as started (keeps 'completed' if it was already done).
  Future<void> startLesson(Sign sign, {SignProgress? previous}) async {
    final uid = _uid;
    if (uid == null) return;
    await _doc(uid, sign.id).set({
      'uid': uid,
      'sign_id': sign.id,
      'unit': sign.unit,
      'status': previous?.completed == true ? 'completed' : 'in_progress',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks the lesson as completed. [previous] is what the path screen already
  /// knows, so the best confidence is never lowered.
  Future<void> completeLesson({
    required Sign sign,
    required double confidence,
    required int quizScore,
    required int quizTotal,
    SignProgress? previous,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final best = previous == null || confidence > previous.bestConfidence
        ? confidence
        : previous.bestConfidence;
    await _doc(uid, sign.id).set({
      'uid': uid,
      'sign_id': sign.id,
      'unit': sign.unit,
      'status': 'completed',
      'best_confidence': best,
      'quiz_score': quizScore,
      'quiz_total': quizTotal,
      if (previous?.completedAt == null)
        'completed_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
