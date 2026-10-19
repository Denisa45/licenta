// lib/vision/hand_tracker.dart
//
// Thin wrapper around the hand_landmarker plugin. That plugin talks to Android
// through JNI (dart:ffi), which does not exist on the web, so it is only imported
// when dart:ffi is available. In Chrome, HandTracker.create() returns null and the
// camera widget shows a message instead.

import 'package:camera/camera.dart';

import 'hand_tracker_stub.dart'
    if (dart.library.ffi) 'hand_tracker_android.dart'
    as impl;

/// 21 MediaPipe landmarks as (x, y, z), x and y as 0..1 fractions of the frame.
typedef Landmarks = List<(double, double, double)>;

abstract class HandTracker {
  /// Landmarks of the first hand, or null when no hand is visible.
  Stream<Landmarks?> get hands;

  /// Sends one camera frame to MediaPipe (results arrive on [hands]).
  void processFrame(CameraImage image, int sensorOrientation);

  void dispose();

  /// Null when hand tracking is not available on this platform.
  static HandTracker? create() => impl.createHandTracker();
}
