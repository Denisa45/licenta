// lib/widgets/dynamic_sign_camera.dart
//
// Camera check for a sign with movement. A moving sign cannot be "held for a
// second", so the learner presses Start, gets a 3-2-1 countdown and then does
// the whole sign in a fixed window (2 s, the same as record_sequences.py).
// The recorded hand path goes through DynamicSignClassifier (GRU/LSTM).

import 'dart:async';

import 'package:flutter/material.dart';

import '../dynamic_sign_classifier.dart';
import '../sign_classifier.dart';
import '../l10n.dart';
import 'sign_camera.dart';

enum _Phase { idle, countdown, recording, result }

class DynamicSignCamera extends StatefulWidget {
  /// Model label the learner should show, or null to just show the best guess.
  final String? target;

  /// Name shown for [target] (for example 'Bună' for the label 'BUNA').
  final String? targetName;

  /// Called after each attempt with the prediction (null: hand not seen enough).
  final ValueChanged<SignPrediction?>? onResult;

  /// Called when [target] was recognized with at least [threshold].
  final VoidCallback? onSuccess;

  final double threshold;

  const DynamicSignCamera({
    super.key,
    this.target,
    this.targetName,
    this.onResult,
    this.onSuccess,
    this.threshold = 0.70,
  });

  @override
  State<DynamicSignCamera> createState() => _DynamicSignCameraState();
}

class _DynamicSignCameraState extends State<DynamicSignCamera> {
  static const _countdown = 3;

  /// Share of the recorded frames that must show the hand (MIN_HAND_FRAMES).
  static const _minHandFrames = 0.6;

  late final Future<DynamicSignClassifier?> _classifier =
      DynamicSignClassifier.load();
  DynamicSignClassifier? _model;

  _Phase _phase = _Phase.idle;
  int _secondsLeft = 0;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  final List<TimedHand> _frames = [];
  int _seenFrames = 0;
  SignPrediction? _result;
  bool _handMissing = false;

  @override
  void initState() {
    super.initState();
    _classifier.then((m) {
      if (mounted) setState(() => _model = m);
    });
  }

  @override
  void didUpdateWidget(DynamicSignCamera old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _timer?.cancel();
    _phase = _Phase.idle;
    _result = null;
    _handMissing = false;
    _frames.clear();
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.countdown;
      _secondsLeft = _countdown;
      _result = null;
      _handMissing = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
        return;
      }
      t.cancel();
      _beginRecording();
    });
  }

  void _beginRecording() {
    final model = _model;
    if (model == null) return;
    setState(() {
      _phase = _Phase.recording;
      _frames.clear();
      _seenFrames = 0;
    });
    _clock
      ..reset()
      ..start();
    _timer = Timer(model.duration, _finish);
  }

  void _onHand(List<(double, double, double)>? hand) {
    if (_phase != _Phase.recording) return;
    _seenFrames++;
    if (hand != null) {
      _frames.add((_clock.elapsedMicroseconds / 1e6, hand));
    }
  }

  void _finish() {
    _clock.stop();
    final model = _model;
    if (!mounted || model == null) return;
    SignPrediction? result;
    if (_frames.length >= 5 && _frames.length >= _minHandFrames * _seenFrames) {
      result = model.classify(List.of(_frames));
    }
    setState(() {
      _phase = _Phase.result;
      _result = result;
      _handMissing = result == null;
    });
    widget.onResult?.call(result);
    final target = widget.target;
    if (result != null &&
        target != null &&
        result.label == target &&
        result.confidence >= widget.threshold) {
      widget.onSuccess?.call();
    }
  }

  String get _status {
    switch (_phase) {
      case _Phase.idle:
        return tr(
          'Apasă Start, apoi fă semnul',
          'Press Start, then do the sign',
        );
      case _Phase.countdown:
        return tr(
          'Pregătește-te... $_secondsLeft',
          'Get ready... $_secondsLeft',
        );
      case _Phase.recording:
        return tr('Acum! Fă semnul', 'Now! Do the sign');
      case _Phase.result:
        final r = _result;
        if (r == null) {
          return tr(
            'Nu am văzut mâna destul de bine',
            'I could not see your hand well enough',
          );
        }
        final name = r.label == widget.target
            ? widget.targetName ?? r.label
            : r.label;
        return '${tr('Semnul', 'Sign')} $name · '
            '${(r.confidence * 100).round()}%';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_model == null) {
      return FutureBuilder(
        future: _classifier,
        builder: (context, snap) => snap.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr(
                      'Modelul pentru semnele cu mișcare nu este încă în '
                          'aplicație (assets/seq_model.json).',
                      'The model for moving signs is not in the app yet '
                          '(assets/seq_model.json).',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
      );
    }

    final r = _result;
    final success =
        r != null &&
        r.label == widget.target &&
        r.confidence >= widget.threshold;
    final busy = _phase == _Phase.countdown || _phase == _Phase.recording;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: SignCamera(
                  staticRecognition: false,
                  statusText: _status,
                  onHand: _onHand,
                ),
              ),
              if (_phase == _Phase.recording)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Icon(Icons.fiber_manual_record, color: cs.error),
                ),
            ],
          ),
        ),
        if (_phase == _Phase.result && widget.target != null) ...[
          const SizedBox(height: 8),
          Text(
            success
                ? tr('Corect!', 'Correct!')
                : _handMissing
                ? tr(
                    'Ține mâna în cadru pe toată durata semnului.',
                    'Keep your hand in the frame for the whole sign.',
                  )
                : tr(
                    'Nu încă. Uită-te din nou la mână și încearcă iar.',
                    'Not yet. Watch the hand again and try once more.',
                  ),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: success ? cs.primary : cs.error,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy ? null : _start,
          icon: const Icon(Icons.videocam),
          label: Text(
            _phase == _Phase.result
                ? tr('Încearcă din nou', 'Try again')
                : tr('Start', 'Start'),
          ),
        ),
      ],
    );
  }
}
