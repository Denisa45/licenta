// lib/screens/lesson_screen.dart
//
// One lesson = one sign, in 3 steps:
//   1. Învață    the hand drawn from robot_pose + the description; the robot
//                hand shows the sign by itself when the step opens
//   2. Încearcă  the camera must recognize the sign (>= 80% held for 1 second)
//   3. Verifică  3 quiz questions
// A word lesson (a sign with 'letters', e.g. DA) has the same steps: the robot
// spells the word, the camera checks the letters one after another, and the
// quiz asks about the word and its letters.
// Feedback is gentle: wrong answers show the right one, nothing is taken away,
// and the lesson is completed whatever the quiz score (spec WEB-08).

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../services/progress_service.dart';
import '../widgets/dynamic_sign_camera.dart';
import '../widgets/robot_button.dart';
import '../widgets/sign_camera.dart';
import '../widgets/sign_widgets.dart';
import '../l10n.dart';

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

  // Word lessons: the letter signs in order, and the one the camera checks now.
  late final List<Sign> _letters = [
    for (final id in sign.letters)
      ...widget.allSigns.where((s) => s.id == id).take(1),
  ];
  int _letterIndex = 0;

  /// The sign the camera checks now: the lesson's sign, or the current letter.
  Sign get _target =>
      sign.isWord && _letters.isNotEmpty ? _letters[_letterIndex] : sign;

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
    if (step == _Step.attempt) _startHintTimer();
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

  void _startHintTimer() {
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && !_recognized) setState(() => _showHint = true);
    });
  }

  /// Word lessons move on to the next letter; the last letter (or a single
  /// sign) completes the step.
  void _onTargetRecognized() {
    if (sign.isWord && _letterIndex + 1 < _letters.length) {
      setState(() {
        _letterIndex++;
        _showHint = false;
      });
      _startHintTimer();
      return;
    }
    _onRecognized();
  }

  void _onReading(SignReading r) {
    final i = r.labels.indexOf(_target.shape);
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
      predicted: source == 'camera'
          ? (sign.isWord ? sign.name : sign.shape)
          : '-',
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
    final target = _target;
    if (r.label == target.shape || r.confidence < 0.6) return null;
    final seen = widget.allSigns.where((s) => s.shape == r.label).firstOrNull;
    if (seen == null) return null;
    final tips = <String>[];
    for (final f in kFingers) {
      final want = (target.robotPose[f] ?? 0) == 1;
      final has = (seen.robotPose[f] ?? 0) == 1;
      final name = fingerName(f);
      if (want && !has) tips.add(tr('ridică $name', 'raise the $name'));
      if (!want && has) tips.add(tr('îndoaie $name', 'bend the $name'));
    }
    if (tips.isEmpty) return null;
    final list = tips.join(tr(' și ', ' and '));
    return tr(
      'Camera vede semnul ${r.label}: $list.',
      'The camera sees sign ${r.label}: $list.',
    );
  }

  // ---------------------------------------------------------------- Verifică

  List<_Question> _buildQuestions() {
    final rnd = Random();
    final isNumber = int.tryParse(sign.name) != null;
    // Wrong answers come from the same unit first (letters with letters,
    // numbers with numbers), then from the other units if there are too few.
    final sameUnit =
        widget.allSigns
            .where((s) => s.id != sign.id && s.unit == sign.unit && !s.isWord)
            .toList()
          ..shuffle(rnd);
    final otherUnits =
        widget.allSigns.where((s) => s.unit != sign.unit && !s.isWord).toList()
          ..shuffle(rnd);
    final others = [...sameUnit, ...otherUnits];

    _Question single(
      String prompt,
      String answer,
      List<String> wrong, {
      Widget? visual,
    }) {
      final options = {
        answer,
        ...wrong.where((w) => w.isNotEmpty),
      }.take(3).toList()..shuffle(rnd);
      return _Question(
        prompt: prompt,
        visual: visual,
        options: options,
        correct: {options.indexOf(answer)},
      );
    }

    if (sign.isWord) return _wordQuestions(single, rnd);

    return [
      single(
        isNumber
            ? tr(
                'Ce număr arată această mână?',
                'Which number does this hand show?',
              )
            : tr(
                'Ce literă arată această mână?',
                'Which letter does this hand show?',
              ),
        sign.name,
        [for (final s in others) s.name],
        visual: HandPoseView(pose: sign.robotPose, height: 160),
      ),
      // Descriptions only work as answers when they exist and differ;
      // otherwise ask which sign has these fingers up.
      if (sign.localDescription.isNotEmpty &&
          others.any(
            (s) =>
                s.localDescription.isNotEmpty &&
                s.localDescription != sign.localDescription,
          ))
        single(
          tr(
            'Care descriere se potrivește semnului ${sign.name}?',
            'Which description matches sign ${sign.name}?',
          ),
          sign.localDescription,
          [for (final s in others) s.localDescription],
        )
      else
        single(
          tr(
            'Care semn se face ridicând ${sign.raisedFingersText}?',
            'Which sign is made by raising the ${sign.raisedFingersText}?',
          ),
          sign.name,
          [
            for (final s in others)
              if (s.raisedFingersText != sign.raisedFingersText) s.name,
          ],
        ),
      _Question(
        prompt: tr(
          'Ce degete sunt ridicate la semnul ${sign.name}?',
          'Which fingers are up in sign ${sign.name}?',
        ),
        hint: tr(
          'Alege toate degetele ridicate.',
          'Choose all the raised fingers.',
        ),
        options: [for (final f in kFingers) fingerName(f)],
        correct: {
          for (var i = 0; i < kFingers.length; i++)
            if (sign.raisedFingers.contains(kFingers[i])) i,
        },
        multi: true,
      ),
    ];
  }

  /// Word lessons: read the word from the hand drawings (names hidden),
  /// recognize one of its letters from a drawing, and say which fingers are up
  /// for another one. None of them can be answered just by reading the word.
  List<_Question> _wordQuestions(
    _Question Function(String, String, List<String>, {Widget? visual}) single,
    Random rnd,
  ) {
    final letterSigns =
        widget.allSigns
            .where((s) => !s.isWord && int.tryParse(s.name) == null)
            .toList()
          ..shuffle(rnd);
    final letterNames = [for (final s in letterSigns) s.name];
    // Other words first; with few words, made-up ones from the known letters.
    final wrongWords = <String>{
      for (final s in widget.allSigns)
        if (s.isWord && s.id != sign.id) s.name,
      [for (final l in _letters.reversed) l.name].join(),
      if (letterNames.isNotEmpty)
        for (var i = 0; i < 6; i++)
          [
            for (final _ in _letters)
              letterNames[rnd.nextInt(letterNames.length)],
          ].join(),
    }..remove(sign.name);

    // Two different letters of the word (by name: MAMA has M and A).
    final distinct = <String, Sign>{
      for (final l in _letters) l.name: l,
    }.values.toList()..shuffle(rnd);
    final shown = distinct.isEmpty ? null : distinct.first;
    final fingers = distinct.length > 1 ? distinct[1] : shown;

    return [
      single(
        tr(
          'Ce cuvânt formează aceste semne?',
          'Which word do these signs spell?',
        ),
        sign.name,
        wrongWords.toList(),
        visual: _LetterRow(letters: _letters, height: 110, showNames: false),
      ),
      if (shown != null)
        single(
          tr(
            'Ce literă din cuvântul ${sign.name} arată această mână?',
            'Which letter of the word ${sign.name} does this hand show?',
          ),
          shown.name,
          [
            for (final s in letterSigns)
              if (s.raisedFingersText != shown.raisedFingersText) s.name,
          ],
          visual: HandPoseView(pose: shown.robotPose, height: 160),
        ),
      if (fingers != null)
        _Question(
          prompt: tr(
            'Ce degete sunt ridicate la litera ${fingers.name}, '
                'din cuvântul ${sign.name}?',
            'Which fingers are up in the letter ${fingers.name}, '
                'in the word ${sign.name}?',
          ),
          hint: tr(
            'Alege toate degetele ridicate.',
            'Choose all the raised fingers.',
          ),
          options: [for (final f in kFingers) fingerName(f)],
          correct: {
            for (var i = 0; i < kFingers.length; i++)
              if (fingers.raisedFingers.contains(kFingers[i])) i,
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
      _Step.learn => tr('Învață', 'Learn'),
      _Step.attempt => tr('Încearcă', 'Try'),
      _Step.quiz => tr('Verifică', 'Check'),
      _Step.done => tr('Gata!', 'Done!'),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: tr('Închide lecția', 'Close the lesson'),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('${sign.kind} ${sign.name} · $title'),
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
    final fingers = [for (final f in sign.raisedFingers) fingerName(f)];
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Card(
                color: cs.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: sign.isWord
                        ? _LetterRow(letters: _letters)
                        : HandPoseView(pose: sign.robotPose),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // The hand shows the sign first, then the child tries it.
              RobotButton(signId: sign.id, autoStart: true),
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
                            '${sign.kind} ${sign.name}',
                            style: text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
                          '${tr('Degete ridicate', 'Raised fingers')}: ${fingers.join(', ')}.',
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
          child: Text(tr('AM ÎNȚELES, ÎNCERC', "GOT IT, LET'S TRY")),
        ),
      ],
    );
  }

  Widget _attemptStep(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final feedback = _fingerFeedback();
    final target = _target;
    final fingers = [for (final f in target.raisedFingers) fingerName(f)];

    return Column(
      children: [
        Text(
          _recognized
              ? sign.isWord
                    ? tr(
                        'Bravo! Ai arătat cuvântul ${sign.name}.',
                        'Well done! You showed the word ${sign.name}.',
                      )
                    : tr(
                        'Bravo! Am recunoscut semnul ${sign.name}.',
                        'Well done! Sign ${sign.name} was recognized.',
                      )
              : sign.isWord
              ? tr(
                  'Arată litera ${target.name} '
                      '(${_letterIndex + 1} din ${_letters.length}) '
                      'și ține-o o secundă.',
                  'Show the letter ${target.name} '
                      '(${_letterIndex + 1} of ${_letters.length}) '
                      'and hold it for a second.',
                )
              : target.motion
              ? tr(
                  'Apasă Start și fă semnul ${sign.name}, cu mișcarea lui, '
                      'în cele 2 secunde.',
                  'Press Start and do sign ${sign.name}, with its movement, '
                      'within the 2 seconds.',
                )
              : tr(
                  'Fă semnul ${sign.name} în fața camerei și ține-l o secundă.',
                  'Show sign ${sign.name} to the camera and hold it for a second.',
                ),
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: _recognized ? cs.primary : null,
          ),
          textAlign: TextAlign.center,
        ),
        if (sign.isWord) ...[
          const SizedBox(height: 8),
          _LetterProgress(
            letters: _letters,
            current: _letterIndex,
            done: _recognized,
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: target.motion
              ? DynamicSignCamera(
                  target: target.shape,
                  targetName: target.name,
                  onSuccess: _onTargetRecognized,
                )
              : SignCamera(
                  target: target.shape,
                  targetName: target.name,
                  onReading: _onReading,
                  onSuccess: _onTargetRecognized,
                ),
        ),
        if (!target.motion &&
            (feedback != null || (_showHint && !_recognized))) ...[
          const SizedBox(height: 8),
          Card(
            color: cs.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                feedback ??
                    tr(
                      'Sfat: ridică doar ${fingers.join(', ')}, cu palma spre '
                          'cameră, la o jumătate de metru de tabletă.',
                      'Tip: raise only the ${fingers.join(', ')}, palm towards '
                          'the camera, about half a metre from the tablet.',
                    ),
                style: TextStyle(color: cs.onSecondaryContainer),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _recognized ? () => _goTo(_Step.quiz) : null,
          child: Text(tr('CONTINUĂ', 'CONTINUE')),
        ),
        if (kDebugMode && !_recognized)
          TextButton(
            onPressed: () {
              _onRecognized(source: 'debug_skip');
              _goTo(_Step.quiz);
            },
            child: Text(
              tr(
                'Sari peste camera (doar debug)',
                'Skip the camera (debug only)',
              ),
            ),
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
                Icon(
                  Icons.emoji_events_outlined,
                  size: 80,
                  color: cs.secondary,
                ),
                const SizedBox(height: 12),
                Text(
                  tr('Lecție terminată!', 'Lesson complete!'),
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr(
                    'Răspunsuri corecte: $_score din ${_questions.length}',
                    'Correct answers: $_score of ${_questions.length}',
                  ),
                  style: text.titleMedium,
                ),
                if (_bestConfidence > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${tr('Recunoaștere cameră', 'Camera recognition')}: '
                    '${(_bestConfidence * 100).round()}%',
                    style: text.titleMedium,
                  ),
                ],
                if (next != null && widget.previous?.completed != true) ...[
                  const SizedBox(height: 20),
                  Text(
                    next.isWord
                        ? tr(
                            'Ai deblocat cuvântul ${next.name}.',
                            'You unlocked the word ${next.name}.',
                          )
                        : tr(
                            'Ai deblocat semnul ${next.name}.',
                            'You unlocked sign ${next.name}.',
                          ),
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
          child: Text(tr('ÎNAPOI LA DRUMUL MEU', 'BACK TO MY PATH')),
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
    final ok =
        _selected.length == q.correct.length &&
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
                tr(
                  'Întrebarea ${widget.number} din ${widget.total}',
                  'Question ${widget.number} of ${widget.total}',
                ),
                style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                q.prompt,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
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
              color: (_correct! ? cs.primary : cs.secondary).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _correct!
                  ? tr('Corect!', 'Correct!')
                  : tr(
                      'Aproape! Răspunsul corect: $answer.',
                      'Almost! The right answer: $answer.',
                    ),
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
          child: Text(
            checked ? tr('CONTINUĂ', 'CONTINUE') : tr('VERIFICĂ', 'CHECK'),
          ),
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
                    ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                    : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                color: selected ? cs.secondary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
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

/// Word lessons: the hand of every letter, with its name under it.
class _LetterRow extends StatelessWidget {
  final List<Sign> letters;
  final double height;

  /// False in the quiz, where the learner has to read the word from the hands.
  final bool showNames;

  const _LetterRow({
    required this.letters,
    this.height = 160,
    this.showNames = true,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final l in letters)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HandPoseView(pose: l.robotPose, height: height),
              if (showNames) ...[
                const SizedBox(height: 8),
                Text(
                  l.name,
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// Word lessons, "Încearcă": the letters of the word, done ones ticked and the
/// current one highlighted.
class _LetterProgress extends StatelessWidget {
  final List<Sign> letters;
  final int current;
  final bool done;

  const _LetterProgress({
    required this.letters,
    required this.current,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (var i = 0; i < letters.length; i++)
          Chip(
            avatar: done || i < current
                ? Icon(Icons.check, color: cs.primary)
                : null,
            label: Text(
              letters[i].name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            backgroundColor: !done && i == current
                ? cs.secondaryContainer
                : cs.surface,
          ),
      ],
    );
  }
}
