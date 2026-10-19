// lib/screens/practice_screen.dart
//
// "Exersare": free camera practice. Shows whatever sign the camera sees, with the
// probability of every sign. Optionally pick a sign to aim for: when it is
// recognized, the attempt is saved in practice_sessions (step 'practice').

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../services/progress_service.dart';
import '../widgets/language_button.dart';
import '../widgets/sign_camera.dart';
import '../l10n.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  late final Future<List<Sign>> _signs = FirebaseFirestore.instance
      .collection('signs')
      .orderBy('order')
      .get()
      .then((s) => s.docs.map(Sign.fromFirestore).toList());

  SignReading? _reading;
  Sign? _target;

  void _onSuccess() {
    final target = _target;
    final reading = _reading;
    if (target == null) return;
    ProgressService.instance.logSession(
      target: target,
      predicted: reading?.label ?? target.name,
      confidence: reading?.confidence ?? 0,
      success: true,
      step: 'practice',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Bravo! Semnul ${target.name} a fost recunoscut.',
            'Well done! Sign ${target.name} was recognized.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Exersare', 'Practice')),
        actions: const [LanguageButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              FutureBuilder<List<Sign>>(
                future: _signs,
                builder: (context, snap) {
                  final signs = snap.data ?? const <Sign>[];
                  return Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ChoiceChip(
                        label: Text(tr('Liber', 'Free')),
                        selected: _target == null,
                        onSelected: (_) => setState(() => _target = null),
                      ),
                      for (final s in signs)
                        ChoiceChip(
                          label: Text(s.name),
                          selected: _target?.id == s.id,
                          onSelected: (_) => setState(() => _target = s),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SignCamera(
                  target: _target?.name,
                  onReading: (r) => setState(() => _reading = r),
                  onSuccess: _onSuccess,
                ),
              ),
              const SizedBox(height: 12),
              if (reading != null && reading.handVisible)
                _ProbabilityBars(reading: reading)
              else
                Text(
                  _target == null
                      ? tr(
                          'Fă orice semn de la 1 la 5.',
                          'Show any sign from 1 to 5.',
                        )
                      : tr(
                          'Fă semnul ${_target!.name} și ține-l o secundă.',
                          'Show sign ${_target!.name} and hold it for a second.',
                        ),
                  style: text.titleMedium,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProbabilityBars extends StatelessWidget {
  final SignReading reading;

  const _ProbabilityBars({required this.reading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < reading.labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    reading.labels[i],
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: reading.probabilities[i],
                      minHeight: 12,
                      color: reading.labels[i] == reading.label
                          ? cs.secondary
                          : cs.primary,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(reading.probabilities[i] * 100).round()}%',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
