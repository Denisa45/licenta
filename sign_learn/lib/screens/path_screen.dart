// lib/screens/path_screen.dart
//
// "Drumul meu": the learning path. One sign per lesson, in the Firestore 'order'.
// The first lesson is always open; lesson N+1 opens when lesson N is completed.
// The progress bar is completed lessons / total lessons.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../services/progress_service.dart';
import '../widgets/language_button.dart';
import '../widgets/sign_widgets.dart';
import 'lesson_screen.dart';
import '../l10n.dart';

String unitTitle(String unit) {
  final m = RegExp(r'^unit(\d+)$', caseSensitive: false).firstMatch(unit);
  return m != null ? '${tr('Unitatea', 'Unit')} ${m.group(1)}' : unit;
}

enum LessonState { locked, open, completed }

class PathScreen extends StatefulWidget {
  const PathScreen({super.key});

  @override
  State<PathScreen> createState() => _PathScreenState();
}

class _PathScreenState extends State<PathScreen> {
  // Created once, so rebuilds do not open new Firestore listeners.
  final _signsStream = FirebaseFirestore.instance
      .collection('signs')
      .orderBy('order')
      .snapshots();
  final _progressStream = ProgressService.instance.watch();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Drumul meu', 'My path')),
        actions: [
          const LanguageButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: tr('Ieșire', 'Sign out'),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
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
              if (progSnap.hasError) {
                return Center(
                  child: Text('${tr('Eroare', 'Error')}: ${progSnap.error}'),
                );
              }
              final progress = progSnap.data ?? const {};
              return _PathList(signs: signs, progress: progress);
            },
          );
        },
      ),
    );
  }
}

class _PathList extends StatelessWidget {
  final List<Sign> signs;
  final Map<String, SignProgress> progress;

  const _PathList({required this.signs, required this.progress});

  @override
  Widget build(BuildContext context) {
    // A lesson is open when every lesson before it is completed.
    final states = <LessonState>[];
    var previousDone = true;
    for (final s in signs) {
      final done = progress[s.id]?.completed ?? false;
      states.add(
        done
            ? LessonState.completed
            : previousDone
            ? LessonState.open
            : LessonState.locked,
      );
      previousDone = done;
    }
    final completed = states.where((s) => s == LessonState.completed).length;

    final children = <Widget>[
      _ProgressHeader(completed: completed, total: signs.length),
    ];
    String? unit;
    for (var i = 0; i < signs.length; i++) {
      final s = signs[i];
      if (s.unit != unit) {
        unit = s.unit;
        children.add(_UnitBanner(title: unitTitle(s.unit)));
      }
      children.add(
        _LessonTile(
          sign: s,
          state: states[i],
          isLast: i == signs.length - 1 || signs[i + 1].unit != s.unit,
          onTap: () => _open(context, i, states[i]),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: children,
        ),
      ),
    );
  }

  void _open(BuildContext context, int index, LessonState state) {
    if (state == LessonState.locked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Termină mai întâi lecția pentru semnul ${signs[index - 1].name}.',
              'First finish the lesson for sign ${signs[index - 1].name}.',
            ),
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          sign: signs[index],
          allSigns: signs,
          previous: progress[signs[index].id],
          nextSign: index + 1 < signs.length ? signs[index + 1] : null,
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int completed;
  final int total;

  const _ProgressHeader({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final value = total == 0 ? 0.0 : completed / total;
    return Card(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              completed == total && total > 0
                  ? tr(
                      'Ai terminat toate lecțiile!',
                      'You finished all the lessons!',
                    )
                  : tr(
                      'Lecții terminate: $completed din $total',
                      'Lessons completed: $completed of $total',
                    ),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 14,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  final String title;

  const _UnitBanner({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: cs.onPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One lesson on the path: a numbered circle on a vertical line, plus a card.
class _LessonTile extends StatelessWidget {
  final Sign sign;
  final LessonState state;
  final bool isLast;
  final VoidCallback onTap;

  const _LessonTile({
    required this.sign,
    required this.state,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final locked = state == LessonState.locked;
    final done = state == LessonState.completed;

    final circleColor = done
        ? cs.primary
        : locked
        ? cs.surfaceContainerHighest
        : cs.secondary;
    final circleText = locked ? cs.onSurfaceVariant : Colors.white;
    final status = switch (state) {
      LessonState.completed => tr('Terminată', 'Completed'),
      LessonState.open => tr('Începe lecția', 'Start the lesson'),
      LessonState.locked => tr('Blocată', 'Locked'),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: done
                      ? Icon(Icons.check, color: circleText)
                      : Text(
                          sign.name,
                          style: TextStyle(
                            color: circleText,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 4,
                      margin: const EdgeInsets.only(top: 4),
                      color: done ? cs.primary : cs.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Card(
                color: locked ? cs.surface.withValues(alpha: 0.6) : cs.surface,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sign.kind} ${sign.name}',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: locked ? cs.onSurfaceVariant : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                status,
                                style: text.bodyMedium?.copyWith(
                                  color: done
                                      ? cs.primary
                                      : locked
                                      ? cs.onSurfaceVariant
                                      : cs.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DifficultyDots(level: sign.difficulty),
                        const SizedBox(width: 8),
                        Icon(
                          locked ? Icons.lock_outline : Icons.chevron_right,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
