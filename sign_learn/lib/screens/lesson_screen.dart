// lib/screens/lesson_screen.dart
//
// One lesson = one sign, in 3 steps:
//   1. Învață    the hand drawn from robot_pose + the description
//   2. Încearcă  the camera must recognize the sign (>= 80% held for 1 second)
//   3. Verifică  3 quiz questions
// Feedback is gentle: wrong answers show the right one, nothing is taken away,
// and the lesson is completed whatever the quiz score (spec WEB-08).

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../services/progress_service.dart';
import '../widgets/sign_camera.dart';
import '../widgets/sign_widgets.dart';

enum _Step { learn, attempt, quiz, done }

class LessonScreen extends StatefulWidget {
  final Sign sign;
  final List<Sign> allSigns;
  final SignProgress? previous;
  final Sign? nextSign;

  const LessonScreen({
    super.key,
    required this.sign,
    required this.allSigns,
    this.previous,
    this.nextSign,
  });

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final _progress = ProgressService.instance;
  _Step _step = _Step.learn;

  // Încearcă
  bool _recognized = false;
  bool _sawHand = false;
  bool _showHint = false;
  double _bestConfidence = 0;
  SignReading? _reading;
  Timer? _hintTimer;

  // Verifică
  late final List<_Question> _questions = _buildQuestions();
  int _questionIndex = 0;
  int _score = 0;

  Sign get sign => widget.sign;

  @override
  void initState() {
    super.initState();
    _progress.startLesson(sign, previous: widget.previous);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    // Closed during the camera step after trying: save it as a failed attempt.
    if (_step == _Step.attempt && !_recognized && _sawHand) {
      _progress.logSession(
        target: sign,
        predicted: _reading?.label ?? '-',
        confidence: _bestConfidence,
        success: false,
        step: 'lesson',
      );
    }
    super.dispose();
  }

  void _goTo(_Step step) {
    setState(() => _step = step);
    if (step == _Step.attempt) {
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(seconds: 20), () {
        if (mounted && !_recognized) setState(() => _showHint = true);
      });
    }
    if (step == _Step.done) {
      _progress.completeLesson(
        sign: sign,
        confidence: _bestConfidence,
        quizScore: _score,
        quizTotal: _questions.length,
        previous: widget.previous,
      );
    }
  }

  // ---------------------------------------------------------------- Încearcă

  void _onReading(SignReading r) {
    final i = r.labels.indexOf(sign.name);
    setState(() {
      _reading = r;
      if (r.handVisible) {
        _sawHand = true;
        if (i >= 0) _bestConfidence = max(_bestConfidence, r.probabilities[i]);
      }
    });
  }

  void _onRecognized({String source = 'camera'}) {
    if (_recognized) return;
    _hintTimer?.cancel();
    setState(() => _recognized = true);
    _progress.logSession(
      target: sign,
      predicted: source == 'camera' ? sign.name : '-',
      confidence: _bestConfidence,
      success: source == 'camera',
      step: 'lesson',
      source: source,
    );
  }

  /// "Camera sees sign 3: bend the thumb" — compares robot_pose of the sign the
  /// camera sees with the target sign, finger by finger.
  String? _fingerFeedback() {
    final r = _reading;
    if (r == null || !r.handVisible || _recognized) return null;
    if (r.label == sign.name || r.confidence < 0.6) return null;
    final seen = widget.allSigns.where((s) => s.name == r.label).firstOrNull;
    if (seen == null) return null;
    final tips = <String>[];
    for (final f in kFingers) {
      final want = (sign.robotPose[f] ?? 0) == 1;
      final has = (seen.robotPose[f] ?? 0) == 1;
      if (want && !has) tips.add('ridică ${kFingerNames[f]}');
      if (!want && has) tips.add('îndoaie ${kFingerNames[f]}');
    }
    if (tips.isEmpty) return null;
    return 'Camera vede semnul ${r.label}. Încearcă să ${tips.join(' și ')}.';
  }

  // ---------------------------------------------------------------- Verifică

  List<_Question> _buildQuestions() {
    final rnd = Random();
    final others = widget.allSigns.where((s) => s.id != sign.id).toList()
      ..shuffle(rnd);

    _Question single(String prompt, String answer, List<String> wrong,
        {Widget? visual}) {
      final options = {answer, ...wrong.where((w) => w.isNotEmpty)}
          .take(3)
          .toList()
        ..shuffle(rnd);
      return _Question(
        prompt: prompt,
        visual: visual,
        options: options,
        correct: {options.indexOf(answer)},
      );
    }

    return [
      single(
        'Ce număr arată această mână?',
        sign.name,
        [for (final s in others) s.name],
        visual: HandPoseView(pose: sign.robotPose, height: 160),
      ),
      // Descriptions only work as answers when they exist and differ;
      // otherwise ask which sign has these fingers up.
      if (sign.description.isNotEmpty &&
          others.any((s) =>
              s.description.isNotEmpty && s.description != sign.description))
        single(
          'Care descriere se potrivește semnului ${sign.name}?',
          sign.description,
          [for (final s in others) s.description],
        )
      else
        single(
          'Care semn se face ridicând ${sign.raisedFingersText}?',
          sign.name,
          [
            for (final s in others)
              if (s.raisedFingersText != sign.raisedFingersText) s.name,
          ],
        ),
      _Question(
        prompt: 'Ce degete sunt ridicate la semnul ${sign.name}?',
        hint: 'Alege toate degetele ridicate.',
        options: [for (final f in kFingers) kFingerNames[f]!],
        correct: {
          for (var i = 0; i < kFingers.length; i++)
            if (sign.raisedFingers.contains(kFingers[i])) i,
        },
        multi: true,
      ),
    ];
  }

  void _onAnswered(bool correct) {
    if (correct) _score++;
  }

  void _nextQuestion() {
    if (_questionIndex + 1 < _questions.length) {
      setState(() => _questionIndex++);
    } else {
      _goTo(_Step.done);
    }
  }

  // ---------------------------------------------------------------- UI

  double get _lessonProgress => switch (_step) {
        _Step.learn => 0.1,
        _Step.attempt => 0.4,
        _Step.quiz => 0.6 + 0.4 * _questionIndex / _questions.length,
        _Step.done => 1,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = switch (_step) {
      _Step.learn => 'Învață',
      _Step.attempt => 'Încearcă',
      _Step.quiz => 'Verifică',
      _Step.done => 'Gata!',
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Închide lecția',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Semnul ${sign.name} · $title'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _lessonProgress),
                duration: const Duration(milliseconds: 400),
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                _Step.learn => _learnStep(context),
                _Step.attempt => _attemptStep(context),
                _Step.quiz => _QuestionView(
                    key: ValueKey(_questionIndex),
                    question: _questions[_questionIndex],
                    number: _questionIndex + 1,
                    total: _questions.length,
                    onAnswered: _onAnswered,
                    onNext: _nextQuestion,
                  ),
                _Step.done => _doneStep(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _learnStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fingers = [for (final f in sign.raisedFingers) kFingerNames[f]!];
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Card(
                color: cs.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: HandPoseView(pose: sign.robotPose)),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: cs.surface,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Semnul ${sign.name}',
                            style: text.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          DifficultyDots(level: sign.difficulty),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(sign.howTo, style: text.bodyLarge),
                      if (fingers.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Degete ridicate: ${fingers.join(', ')}.',
                          style: text.bodyLarge?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => _goTo(_Step.attempt),
          child: const Text('AM ÎNȚELES, ÎNCERC'),
        ),
      ],
    );
  }

  Widget _attemptStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final feedback = _fingerFeedback();
    final fingers = [for (final f in sign.raisedFingers) kFingerNames[f]!];

    return Column(
      children: [
        Text(
          _recognized
              ? 'Bravo! Am recunoscut semnul ${sign.name}.'
              : 'Fă semnul ${sign.name} în fața camerei și ține-l o secundă.',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: _recognized ? cs.primary : null,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SignCamera(
            target: sign.name,
            onReading: _onReading,
            onSuccess: _onRecognized,
          ),
        ),
        if (feedback != null || (_showHint && !_recognized)) ...[
          const SizedBox(height: 8),
          Card(
            color: cs.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                feedback ??
                    'Sfat: ridică doar ${fingers.join(', ')}, cu palma spre '
                        'cameră, la o jumătate de metru de tabletă.',
                style: TextStyle(color: cs.onSecondaryContainer),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _recognized ? () => _goTo(_Step.quiz) : null,
          child: const Text('CONTINUĂ'),
        ),
        if (kDebugMode && !_recognized)
          TextButton(
            onPressed: () {
              _onRecognized(source: 'debug_skip');
              _goTo(_Step.quiz);
            },
            child: const Text('Sari peste camera (doar debug)'),
          ),
      ],
    );
  }

  Widget _doneStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final next = widget.nextSign;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_outlined, size: 80, color: cs.secondary),
                const SizedBox(height: 12),
                Text(
                  'Lecție terminată!',
                  style:
                      text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Text(
                  'Răspunsuri corecte: $_score din ${_questions.length}',
                  style: text.titleMedium,
                ),
                if (_bestConfidence > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Recunoaștere cameră: ${(_bestConfidence * 100).round()}%',
                    style: text.titleMedium,
                  ),
                ],
                if (next != null &&
                    widget.previous?.completed != true) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Ai deblocat semnul ${next.name}.',
                    style: text.titleMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ÎNAPOI LA DRUMUL MEU'),
        ),
      ],
    );
  }
}

class _Question {
  final String prompt;
  final String? hint;
  final Widget? visual;
  final List<String> options;
  final Set<int> correct;
  final bool multi;

  const _Question({
    required this.prompt,
    required this.options,
    required this.correct,
    this.hint,
    this.visual,
    this.multi = false,
  });
}

class _QuestionView extends StatefulWidget {
  final _Question question;
  final int number;
  final int total;
  final ValueChanged<bool> onAnswered;
  final VoidCallback onNext;

  const _QuestionView({
    super.key,
    required this.question,
    required this.number,
    required this.total,
    required this.onAnswered,
    required this.onNext,
  });

  @override
  State<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<_QuestionView> {
  final _selected = <int>{};
  bool? _correct; // null until checked

  _Question get q => widget.question;

  void _tap(int i) {
    if (_correct != null) return;
    setState(() {
      if (q.multi) {
        if (!_selected.remove(i)) _selected.add(i);
      } else {
        _selected
          ..clear()
          ..add(i);
      }
    });
  }

  void _check() {
    final ok = _selected.length == q.correct.length &&
        _selected.containsAll(q.correct);
    setState(() => _correct = ok);
    widget.onAnswered(ok);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final checked = _correct != null;
    final answer = [for (final i in q.correct) q.options[i]].join(', ');

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Text(
                'Întrebarea ${widget.number} din ${widget.total}',
                style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                q.prompt,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              if (q.hint != null) ...[
                const SizedBox(height: 4),
                Text(q.hint!, textAlign: TextAlign.center),
              ],
              if (q.visual != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: cs.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: q.visual),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    text: q.options[i],
                    multi: q.multi,
                    selected: _selected.contains(i),
                    // After checking, the right answers are shown in blue.
                    highlight: checked && q.correct.contains(i),
                    onTap: () => _tap(i),
                  ),
                ),
            ],
          ),
        ),
        if (checked)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_correct! ? cs.primary : cs.secondary)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _correct! ? 'Corect!' : 'Aproape! Răspunsul corect: $answer.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _correct! ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        FilledButton(
          onPressed: checked
              ? widget.onNext
              : _selected.isEmpty
                  ? null
                  : _check,
          child: Text(checked ? 'CONTINUĂ' : 'VERIFICĂ'),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String text;
  final bool multi;
  final bool selected;
  final bool highlight;
  final VoidCallback onTap;

  const _OptionTile({
    required this.text,
    required this.multi,
    required this.selected,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = highlight
        ? cs.primary
        : selected
            ? cs.secondary
            : cs.outlineVariant;
    return Material(
      color: selected ? cs.secondary.withValues(alpha: 0.12) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                    : (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                color: selected ? cs.secondary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (highlight) Icon(Icons.check_circle, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
