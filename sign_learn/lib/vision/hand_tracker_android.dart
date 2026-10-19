import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import 'hand_tracker.dart';

HandTracker? createHandTracker() {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  return _AndroidHandTracker();
}

class _AndroidHandTracker implements HandTracker {
  final HandLandmarkerPlugin _plugin = HandLandmarkerPlugin.create(
    numHands: 1,
    minHandDetectionConfidence: 0.6,
    delegate: HandLandmarkerDelegate.cpu,
  );

  @override
  Stream<Landmarks?> get hands => _plugin.landmarkStream.map((hands) {
        if (hands.isEmpty || hands.first.landmarks.length != 21) return null;
        return [for (final l in hands.first.landmarks) (l.x, l.y, l.z)];
      });

  @override
  void processFrame(CameraImage image, int sensorOrientation) {
    try {
      _plugin.processFrame(image, sensorOrientation); // fire and forget
    } catch (e) {
      debugPrint('processFrame error: $e');
    }
  }

  @override
  void dispose() => _plugin.dispose();
}
