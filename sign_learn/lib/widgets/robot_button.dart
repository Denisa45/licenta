// lib/widgets/robot_button.dart
//
// "Arată pe mâna robotică": sends the sign to the Pi (RobotService) and shows
// the command status under the button. Used in the lesson and in Exersare.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/robot_service.dart';
import '../l10n.dart';

class RobotButton extends StatefulWidget {
  final String signId;

  /// Send the sign once, as soon as the button appears (lesson "Învață" step).
  final bool autoStart;

  const RobotButton({super.key, required this.signId, this.autoStart = false});

  @override
  State<RobotButton> createState() => _RobotButtonState();
}

class _RobotButtonState extends State<RobotButton> {
  // The Pi drops commands older than this (hw/command_listener.py MAX_AGE), so
  // a command still pending after it means the hand is off or not connected.
  static const _timeout = Duration(seconds: 20);

  String? _status;
  StreamSubscription<String>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _show();
  }

  @override
  void didUpdateWidget(RobotButton old) {
    super.didUpdateWidget(old);
    if (old.signId != widget.signId) _reset();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _sub?.cancel();
    _timer?.cancel();
    _sub = null;
    _status = null;
  }

  Future<void> _show() async {
    final signId = widget.signId;
    setState(() => _status = 'pending');
    _timer?.cancel();
    _timer = Timer(_timeout, () {
      if (mounted && _status == 'pending') setState(() => _status = 'offline');
    });
    try {
      final status = await RobotService.instance.showSign(signId);
      await _sub?.cancel();
      if (!mounted || signId != widget.signId) return;
      _sub = status.listen((s) {
        // A late 'pending' snapshot must not hide the offline message.
        if (mounted && !(s == 'pending' && _status == 'offline')) {
          setState(() => _status = s);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'error');
    }
  }

  String get _statusText => switch (_status) {
    'pending' => tr('Se trimite la mână...', 'Sending to the hand...'),
    'processing' => tr('Mâna arată semnul', 'The hand is showing the sign'),
    'completed' => tr('Gata', 'Done'),
    'offline' || 'expired' => tr(
      'Mâna robotică nu răspunde. Este pornită?',
      'The robot hand is not answering. Is it on?',
    ),
    _ => tr('Mâna nu a putut arăta semnul', 'The hand could not show the sign'),
  };

  bool get _busy => _status == 'pending' || _status == 'processing';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _show,
          icon: const Icon(Icons.back_hand_outlined),
          label: Text(tr('ARATĂ PE MÂNA ROBOTICĂ', 'SHOW ON THE ROBOT HAND')),
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_statusText, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}
