// lib/services/progress_service.dart
//
// Citește și scrie progresul utilizatorului prin server (backend/):
//   GET  /progress                    progresul pe fiecare semn (lecție)
//   POST /progress/{sign}/start       lecția începută
//   POST /progress/{sign}/complete    lecția terminată
//   GET  /sessions, POST /sessions    încercările cu camera
//
// Serverul știe cine e utilizatorul din token, deci fiecare vede doar datele lui.
// watch() și watchSessions() reîncarcă datele după fiecare scriere, ca ecranele
// să se actualizeze singure (cum făceau înainte ascultătorii Firestore).

import 'dart:async';

import '../models/sign.dart';
import 'api_client.dart';

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
    completedAt: parseDate(d['completed_at']),
  );
}

/// Data trimisă de server (text ISO 8601, UTC), în ora locală.
DateTime? parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

class ProgressService {
  ProgressService._();
  static final instance = ProgressService._();

  final _api = ApiClient.instance;

  /// Anunță că progresul s-a schimbat, ca watch() să reîncarce datele.
  final _changes = StreamController<void>.broadcast();

  Future<Map<String, SignProgress>> fetch() async {
    final list = await _api.get('/progress') as List;
    return {
      for (final d in list)
        (d['sign_id'] ?? '').toString(): SignProgress.fromMap(
          d as Map<String, dynamic>,
        ),
    };
  }

  /// Încercările cu camera, cele mai noi primele. 'timestamp' e DateTime.
  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final list = await _api.get('/sessions') as List;
    return [
      for (final d in list)
        {...d as Map<String, dynamic>, 'timestamp': parseDate(d['timestamp'])},
    ];
  }

  /// Progresul utilizatorului pe fiecare semn, actualizat după fiecare scriere.
  Stream<Map<String, SignProgress>> watch() => _watch(fetch);

  /// Încercările cu camera, actualizate după fiecare încercare nouă.
  Stream<List<Map<String, dynamic>>> watchSessions() => _watch(fetchSessions);

  /// Încarcă datele când ecranul începe să asculte și din nou după fiecare
  /// scriere. Când ecranul se închide (cancel), nu mai ascultă schimbările.
  Stream<T> _watch<T>(Future<T> Function() load) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    var loadedOnce = false;

    Future<void> refresh() async {
      try {
        final value = await load();
        loadedOnce = true;
        if (!controller.isClosed) controller.add(value);
      } catch (e, st) {
        // Fără conexiune după prima încărcare: păstrăm datele vechi.
        if (!loadedOnce && !controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        refresh();
        changes = _changes.stream.listen((_) => refresh());
      },
      onCancel: () async {
        await changes?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  void _changed() => _changes.add(null);

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
    await _api.post('/sessions', {
      'target_sign': target.id,
      'predicted_sign': predicted,
      'confidence': confidence.clamp(0.0, 1.0),
      'success': success,
      'step': step,
      'source': source,
    });
    _changed();
  }

  /// Marks the lesson as started (the server keeps 'completed' if it was done).
  Future<void> startLesson(Sign sign, {SignProgress? previous}) async {
    await _api.post('/progress/${Uri.encodeComponent(sign.id)}/start');
    _changed();
  }

  /// Marks the lesson as completed. The server never lowers the best confidence
  /// and keeps the first completion date.
  Future<void> completeLesson({
    required Sign sign,
    required double confidence,
    required int quizScore,
    required int quizTotal,
    SignProgress? previous,
  }) async {
    await _api.post('/progress/${Uri.encodeComponent(sign.id)}/complete', {
      'confidence': confidence.clamp(0.0, 1.0),
      'quiz_score': quizScore,
      'quiz_total': quizTotal,
    });
    _changed();
  }
}
