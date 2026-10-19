// lib/widgets/sign_camera.dart
//
// Reusable camera + recognition widget:
// front camera -> HandTracker (21 landmarks) -> optional rotate/mirror ->
// rescale to the training webcam proportions -> SignClassifier -> smoothed probs.
//
// Used by the free practice tab (Exersare) and by the "Încearcă" step of a lesson.

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sign_classifier.dart';
import '../vision/hand_tracker.dart';

/// One smoothed result from the camera.
class SignReading {
  final bool handVisible;
  final String label;
  final double confidence;
  final List<double> probabilities;
  final List<String> labels;

  const SignReading({
    required this.handVisible,
    required this.label,
    required this.confidence,
    required this.probabilities,
    required this.labels,
  });
}

class SignCamera extends StatefulWidget {
  /// Size of the webcam frames used to record the training data (record_takes.py).
  /// Landmarks are 0..1 fractions of the frame, so frames with a different shape
  /// would stretch the hand differently. Check yours (in .venv-record) with:
  ///   python -c "import cv2; c=cv2.VideoCapture(0, cv2.CAP_DSHOW); print(c.read()[1].shape)"
  /// It prints (height, width, 3).
  static const double trainW = 640;
  static const double trainH = 480;

  /// Quarter turns (clockwise) applied to the landmarks before classifying, for
  /// each way the tablet is held. Android 16 does not keep tablet apps in
  /// portrait, and the camera frames do not turn with the screen, so the turn
  /// depends on how the tablet is held. Measured on the Galaxy Tab S9 FE+:
  /// portrait with the camera on the right side -> 270°, landscape with the
  /// camera on top -> 0°. Check the other two with the Rotire button (it changes
  /// only the value of the current orientation) and write them here.
  /// Not final, so the debug buttons can change them for the whole session.
  static final Map<DeviceOrientation, int> turnsFor = {
    DeviceOrientation.portraitUp: 3,
    DeviceOrientation.landscapeLeft: 0,
    DeviceOrientation.portraitDown: 1,
    DeviceOrientation.landscapeRight: 2,
  };
  static bool mirror = false;

  /// Label the learner should show (for example '2'), or null for free practice.
  final String? target;

  /// Called with every smoothed reading (about 15 times per second).
  final ValueChanged<SignReading>? onReading;

  /// Called when [target] was recognized with at least [threshold] confidence
  /// for [holdTime] without interruption. Fires again only after the sign was
  /// let go and shown again.
  final VoidCallback? onSuccess;

  final double threshold;
  final Duration holdTime;

  /// Rotate / Mirror buttons and the frame info line.
  final bool showDebugControls;

  const SignCamera({
    super.key,
    this.target,
    this.onReading,
    this.onSuccess,
    this.threshold = 0.80,
    this.holdTime = const Duration(seconds: 1),
    this.showDebugControls = kDebugMode,
  });

  @override
  State<SignCamera> createState() => _SignCameraState();
}

class _SignCameraState extends State<SignCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  HandTracker? _tracker;
  SignClassifier? _classifier;
  StreamSubscription<Landmarks?>? _sub;
  String? _error;
  bool _unsupported = false;
  bool _disposed = false;
  bool _starting = false;

  // Size of the camera frame after the sensor rotation.
  int _frameW = 0;
  int _frameH = 0;

  List<double>? _smoothed;
  String _label = '-';
  double _confidence = 0;
  bool _handVisible = false;
  String _debug = '';
  DateTime _lastUi = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _holdStart;
  double _holdProgress = 0;
  bool _succeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didUpdateWidget(SignCamera old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _holdStart = null;
      _holdProgress = 0;
      _succeeded = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera when the app goes to the background, reopen it after.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stop();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting || _disposed) return;
    _starting = true;
    try {
      _classifier ??= await SignClassifier.load();

      final tracker = HandTracker.create();
      if (tracker == null) {
        if (mounted) setState(() => _unsupported = true);
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        tracker.dispose();
        if (mounted) setState(() => _error = 'Nu am găsit nicio cameră.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        tracker.dispose();
        return;
      }

      _tracker = tracker;
      _controller = controller;
      _sub = tracker.hands.listen(_onHands);
      await controller.startImageStream(
        (image) => _onFrame(image, camera.sensorOrientation),
      );
      if (mounted) setState(() => _error = null);
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _starting = false;
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller
          .stopImageStream()
          .catchError((_) {})
          .whenComplete(() => controller.dispose());
    }
    _tracker?.dispose();
    _tracker = null;
    _smoothed = null;
    _handVisible = false;
    if (mounted && !_disposed) setState(() {});
  }

  DeviceOrientation get _orientation =>
      _controller?.value.deviceOrientation ?? DeviceOrientation.portraitUp;

  void _onFrame(CameraImage image, int sensorOrientation) {
    final tracker = _tracker;
    if (_disposed || tracker == null) return;
    final swap = sensorOrientation == 90 || sensorOrientation == 270;
    _frameW = swap ? image.height : image.width;
    _frameH = swap ? image.width : image.height;
    tracker.processFrame(image, sensorOrientation);
  }

  void _onHands(Landmarks? hand) {
    final classifier = _classifier;
    if (_disposed || classifier == null) return;

    if (hand == null || _frameW == 0) {
      _smoothed = null;
      _holdStart = null;
      _succeeded = false;
      _holdProgress = 0;
      _publish(handVisible: false);
      return;
    }

    var pts = hand;
    var w = _frameW.toDouble();
    var h = _frameH.toDouble();

    // Turn the points to match how the tablet is held, and/or mirror them.
    final orientation = _orientation;
    final turns = SignCamera.turnsFor[orientation] ?? 0;
    for (var i = 0; i < turns; i++) {
      pts = [for (final (x, y, z) in pts) (1.0 - y, x, z)];
      final t = w;
      w = h;
      h = t;
    }
    if (SignCamera.mirror) {
      pts = [for (final (x, y, z) in pts) (1.0 - x, y, z)];
    }

    // Give x and y the same proportions they had in the training frames,
    // then normalize exactly like the Python code.
    const tw = SignCamera.trainW, th = SignCamera.trainH;
    final scaled = [
      for (final (x, y, z) in pts) (x * w * th, y * h * tw, z * w * th),
    ];
    final probs = classifier.probabilities(SignClassifier.normalize(scaled));

    // Smooth over a few frames so the answer does not flicker.
    final prev = _smoothed;
    final sm = prev == null
        ? probs
        : [
            for (var i = 0; i < probs.length; i++)
              prev[i] * 0.65 + probs[i] * 0.35,
          ];
    _smoothed = sm;

    var best = 0;
    for (var i = 1; i < sm.length; i++) {
      if (sm[i] > sm[best]) best = i;
    }
    _label = classifier.labels[best];
    _confidence = sm[best];

    // Fingertip (8) minus wrist (0). With the hand held up and the points
    // upright, dy should be clearly negative and dx close to 0.
    final dx = pts[8].$1 - pts[0].$1;
    final dy = pts[8].$2 - pts[0].$2;
    _debug =
        '${orientation.name} ${turns * 90}°  cadru ${_frameW}x$_frameH  '
        'vârf arătător - încheietură: '
        'dx=${dx.toStringAsFixed(2)} dy=${dy.toStringAsFixed(2)}';

    _updateHold();
    _publish(handVisible: true);
  }

  void _updateHold() {
    final target = widget.target;
    if (target == null) return;
    if (_label == target && _confidence >= widget.threshold) {
      if (_succeeded) return;
      final now = DateTime.now();
      _holdStart ??= now;
      final held = now.difference(_holdStart!);
      _holdProgress = (held.inMilliseconds / widget.holdTime.inMilliseconds)
          .clamp(0, 1);
      if (held >= widget.holdTime) {
        _succeeded = true;
        _holdProgress = 1;
        widget.onSuccess?.call();
      }
    } else {
      // The sign was let go: it can be recognized again next time.
      _holdStart = null;
      _holdProgress = 0;
      _succeeded = false;
    }
  }

  void _publish({required bool handVisible}) {
    _handVisible = handVisible;
    final now = DateTime.now();
    if (now.difference(_lastUi).inMilliseconds < 66) return; // ~15 per second
    _lastUi = now;
    final classifier = _classifier;
    if (classifier != null) {
      widget.onReading?.call(
        SignReading(
          handVisible: handVisible,
          label: _label,
          confidence: _confidence,
          probabilities: _smoothed ?? List.filled(classifier.labels.length, 0),
          labels: classifier.labels,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  Widget _message(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.primary),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    final cs = Theme.of(context).colorScheme;
    final target = widget.target;
    final matching = target != null && _label == target && _handVisible;
    final text = !_handVisible
        ? 'Arată mâna în fața camerei'
        : 'Semnul $_label · ${(_confidence * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (target != null) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: _holdProgress,
                strokeWidth: 4,
                color: cs.secondary,
                backgroundColor: cs.secondary.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: matching ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            OutlinedButton(
              onPressed: () => setState(() {
                final o = _orientation;
                SignCamera.turnsFor[o] =
                    ((SignCamera.turnsFor[o] ?? 0) + 1) % 4;
                _smoothed = null;
              }),
              child: Text(
                'Rotire ${(SignCamera.turnsFor[_orientation] ?? 0) * 90}°',
              ),
            ),
            OutlinedButton(
              onPressed: () => setState(() {
                SignCamera.mirror = !SignCamera.mirror;
                _smoothed = null;
              }),
              child: Text('Oglindire: ${SignCamera.mirror ? 'da' : 'nu'}'),
            ),
          ],
        ),
        Text(
          _debug,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    Widget view;
    if (_unsupported) {
      view = _message(
        Icons.tablet_android,
        'Camera și recunoașterea mâinii funcționează doar pe tableta Android.',
      );
    } else if (_error != null) {
      view = _message(Icons.error_outline, 'Eroare cameră: $_error');
    } else if (controller == null || !controller.value.isInitialized) {
      view = const Center(child: CircularProgressIndicator());
    } else {
      view = Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          // CameraPreview sizes itself for portrait or landscape.
          child: Stack(
            children: [
              CameraPreview(controller),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Center(child: _overlay()),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: view),
        if (widget.showDebugControls && !_unsupported) _debugControls(),
      ],
    );
  }
}
