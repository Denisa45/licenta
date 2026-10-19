// lib/screens/practice_screen.dart
//
// Camera -> hand_landmarker (21 landmarks) -> SignClassifier -> predicted sign.
// First version for testing on the tablet: free practice (shows whatever sign it
// sees), with two debug buttons (Rotate / Mirror) in case the landmarks come out
// turned or flipped compared with the webcam data the model was trained on.

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../sign_classifier.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  // Size of the webcam frames used to record the training data (record_takes.py).
  // Landmarks are 0..1 fractions of the frame, so frames with a different shape
  // would stretch the hand differently. Check yours (in .venv-record) with:
  //   python -c "import cv2; c=cv2.VideoCapture(0, cv2.CAP_DSHOW); print(c.read()[1].shape)"
  // It prints (height, width, 3). Change these two numbers if it is not 480 x 640.
  static const double _trainW = 640;
  static const double _trainH = 480;

  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  SignClassifier? _classifier;
  StreamSubscription<List<Hand>>? _sub;
  String? _error;
  bool _disposed = false;

  // Debug switches (tap the buttons under the camera).
  int _rotation = 0; // quarter turns clockwise
  bool _mirror = false;

  // Size of the camera frame after the sensor rotation.
  int _frameW = 0;
  int _frameH = 0;

  // Latest result (smoothed over a few frames).
  List<double>? _smoothed;
  String _label = '-';
  double _confidence = 0;
  String _debug = '';
  bool _handVisible = false;
  DateTime _lastUi = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // Keep the screen upright so the camera frames match the sensor rotation.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  Future<void> _init() async {
    try {
      final classifier = await SignClassifier.load();
      debugPrint('SignClassifier selfTest, largest difference: ${classifier.selfTest()}');

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found');
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
      if (!mounted) {
        await controller.dispose();
        return;
      }

      final plugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.cpu,
      );

      _classifier = classifier;
      _plugin = plugin;
      _controller = controller;
      _sub = plugin.landmarkStream.listen(_onHands);
      await controller.startImageStream(
        (image) => _onFrame(image, camera.sensorOrientation),
      );
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onFrame(CameraImage image, int sensorOrientation) {
    final plugin = _plugin;
    if (_disposed || plugin == null) return;
    final swap = sensorOrientation == 90 || sensorOrientation == 270;
    _frameW = swap ? image.height : image.width;
    _frameH = swap ? image.width : image.height;
    try {
      plugin.processFrame(image, sensorOrientation); // fire and forget
    } catch (e) {
      debugPrint('processFrame error: $e');
    }
  }

  void _onHands(List<Hand> hands) {
    final classifier = _classifier;
    if (_disposed || classifier == null) return;

    if (hands.isEmpty || hands.first.landmarks.length != 21 || _frameW == 0) {
      _smoothed = null;
      _publish(handVisible: false);
      return;
    }

    var pts = <(double, double, double)>[
      for (final l in hands.first.landmarks) (l.x, l.y, l.z),
    ];
    var w = _frameW.toDouble();
    var h = _frameH.toDouble();

    // Debug options: turn the points a quarter turn clockwise, and/or mirror them.
    for (var i = 0; i < _rotation; i++) {
      pts = [for (final (x, y, z) in pts) (1.0 - y, x, z)];
      final t = w;
      w = h;
      h = t;
    }
    if (_mirror) {
      pts = [for (final (x, y, z) in pts) (1.0 - x, y, z)];
    }

    // Give x and y the same proportions they had in the training frames
    // (see _trainW / _trainH), then normalize exactly like the Python code.
    final scaled = [
      for (final (x, y, z) in pts) (x * w * _trainH, y * h * _trainW, z * w * _trainH),
    ];
    final probs = classifier.probabilities(SignClassifier.normalize(scaled));

    // Smooth over a few frames so the answer does not flicker.
    final prev = _smoothed;
    final sm = prev == null
        ? probs
        : [for (var i = 0; i < probs.length; i++) prev[i] * 0.65 + probs[i] * 0.35];
    _smoothed = sm;

    var best = 0;
    for (var i = 1; i < sm.length; i++) {
      if (sm[i] > sm[best]) best = i;
    }
    _label = classifier.labels[best];
    _confidence = sm[best];

    // Fingertip (8) minus wrist (0). With the hand held up and the points upright,
    // dy should be clearly negative and dx close to 0.
    final dx = pts[8].$1 - pts[0].$1;
    final dy = pts[8].$2 - pts[0].$2;
    _debug = 'frame ${_frameW}x$_frameH   index tip - wrist:  dx=${dx.toStringAsFixed(2)}  dy=${dy.toStringAsFixed(2)}';

    _publish(handVisible: true);
  }

  void _publish({required bool handVisible}) {
    _handVisible = handVisible;
    final now = DateTime.now();
    if (now.difference(_lastUi).inMilliseconds < 66) return; // about 15 updates per second
    _lastUi = now;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _sub?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller
          .stopImageStream()
          .catchError((_) {})
          .whenComplete(() => controller.dispose());
    }
    _plugin?.dispose();
    super.dispose();
  }

  Widget _panel(BuildContext context) {
    final classifier = _classifier;
    final probs = _smoothed;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _handVisible
                ? 'Sign $_label  (${(_confidence * 100).round()}%)'
                : 'Show your hand to the camera',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (classifier != null && probs != null)
            Wrap(
              spacing: 14,
              children: [
                for (var i = 0; i < probs.length; i++)
                  Text('${classifier.labels[i]}: ${(probs[i] * 100).round()}%'),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => setState(() {
                  _rotation = (_rotation + 1) % 4;
                  _smoothed = null;
                }),
                child: Text('Rotate ${_rotation * 90}°'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _mirror = !_mirror;
                  _smoothed = null;
                }),
                child: Text('Mirror: ${_mirror ? 'on' : 'off'}'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_debug, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error: $_error', textAlign: TextAlign.center),
        ),
      );
    } else if (controller == null || !controller.value.isInitialized) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            ),
          ),
          _panel(context),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: SafeArea(child: body),
    );
  }
}
