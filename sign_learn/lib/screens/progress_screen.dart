// lib/screens/progress_screen.dart
//
// "Progres": summary of the lessons (from progress/) and of the camera attempts
// (from practice_sessions/) of the signed-in user.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../services/progress_service.dart';
import '../widgets/language_button.dart';
import '../l10n.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _signsStream = FirebaseFirestore.instance
      .collection('signs')
      .orderBy('order')
      .snapshots();
  final _progressStream = ProgressService.instance.watch();
  // Filtered by uid only and sorted here, so no composite index is needed.
  final _sessionsStream = FirebaseFirestore.instance
      .collection('practice_sessions')
      .where('uid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Progres', 'Progress')),
        actions: const [LanguageButton()],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _signsStream,
        builder: (context, signSnap) {
          if (signSnap.hasError) {
            return Center(
              child: Text('${tr('Eroare', 'Error')}: ${signSnap.error}'),
            );
          }
          if (!signSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final signs = signSnap.data!.docs.map(Sign.fromFirestore).toList();
          return StreamBuilder<Map<String, SignProgress>>(
            stream: _progressStream,
            builder: (context, progSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _sessionsStream,
                builder: (context, sessSnap) {
                  final error = progSnap.error ?? sessSnap.error;
                  if (error != null) {
                    return Center(
                      child: Text('${tr('Eroare', 'Error')}: $error'),
                    );
                  }
                  return _ProgressBody(
                    signs: signs,
                    progress: progSnap.data ?? const {},
                    sessions: [
                      for (final d in sessSnap.data?.docs ?? const []) d.data(),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  final List<Sign> signs;
  final Map<String, SignProgress> progress;
  final List<Map<String, dynamic>> sessions;

  const _ProgressBody({
    required this.signs,
    required this.progress,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final completed = signs
        .where((s) => progress[s.id]?.completed ?? false)
        .length;
    var quizScore = 0, quizTotal = 0;
    for (final p in progress.values) {
      quizScore += p.quizScore;
      quizTotal += p.quizTotal;
    }
    final camera = sessions.where((s) => s['source'] != 'debug_skip').toList();
    final successes = camera.where((s) => s['success'] == true).length;

    final recent = [...camera]
      ..sort((a, b) {
        final ta = a['timestamp'] as Timestamp?;
        final tb = b['timestamp'] as Timestamp?;
        if (ta == null || tb == null) return ta == null ? -1 : 1;
        return tb.compareTo(ta);
      });
    final names = {for (final s in signs) s.id: s.name};

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _StatCard(
                  label: tr('Lecții terminate', 'Lessons completed'),
                  value: '$completed / ${signs.length}',
                ),
                _StatCard(
                  label: tr('Răspunsuri corecte', 'Correct answers'),
                  value: quizTotal == 0
                      ? '-'
                      : '${(100 * quizScore / quizTotal).round()}%',
                ),
                _StatCard(
                  label: tr('Încercări cu camera', 'Camera attempts'),
                  value: '${camera.length}',
                ),
                _StatCard(
                  label: tr('Reușite', 'Successful'),
                  value: camera.isEmpty
                      ? '-'
                      : '${(100 * successes / camera.length).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(tr('Pe semne', 'By sign'), style: text.titleLarge),
            const SizedBox(height: 8),
            for (final s in signs) _SignRow(sign: s, progress: progress[s.id]),
            const SizedBox(height: 20),
            Text(
              tr('Ultimele încercări', 'Latest attempts'),
              style: text.titleLarge,
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              Text(
                tr(
                  'Încă nu ai încercat niciun semn cu camera.',
                  'You have not tried any sign with the camera yet.',
                ),
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            for (final s in recent.take(10))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s['success'] == true
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: s['success'] == true ? cs.primary : cs.secondary,
                ),
                title: Text(
                  'Semnul ${names[s['target_sign']] ?? s['target_sign']}'
                  '${s['step'] == 'practice' ? ' · exersare' : ' · lecție'}',
                ),
                subtitle: Text(
                  'Recunoscut: ${s['predicted_sign']} · '
                  '${(((s['confidence'] as num?) ?? 0) * 100).round()}%'
                  '${_date(s['timestamp'] as Timestamp?)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _date(Timestamp? t) {
    if (t == null) return '';
    final d = t.toDate();
    String two(int v) => v.toString().padLeft(2, '0');
    return ' · ${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: cs.surface,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              value,
              style: text.headlineMedium?.copyWith(
                color: cs.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignRow extends StatelessWidget {
  final Sign sign;
  final SignProgress? progress;

  const _SignRow({required this.sign, this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = progress;
    final status = p == null
        ? tr('Neînceput', 'Not started')
        : p.completed
        ? tr('Terminat', 'Completed')
        : tr('În lucru', 'In progress');
    final details = [
      if (p != null && p.quizTotal > 0) 'quiz ${p.quizScore}/${p.quizTotal}',
      if (p != null && p.bestConfidence > 0)
        '${tr('cameră', 'camera')} ${(p.bestConfidence * 100).round()}%',
      if (p != null && p.attempts > 0)
        '${p.attempts} ${tr('încercări', 'attempts')}',
    ].join(' · ');
    return Card(
      color: cs.surface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: p?.completed == true
              ? cs.primary
              : cs.surfaceContainerHighest,
          foregroundColor: p?.completed == true
              ? cs.onPrimary
              : cs.onSurfaceVariant,
          child: Text(
            sign.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          status,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: details.isEmpty ? null : Text(details),
      ),
    );
  }
}
