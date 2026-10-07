import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:sensors_plus/sensors_plus.dart';

/// Detects shaking from linear acceleration samples (gravity removed).
/// A shake is several strong movements within a short window.
class ShakeDetector {
  ShakeDetector({
    this.threshold = 12,
    this.minPeaks = 3,
    this.window = const Duration(milliseconds: 700),
    this.cooldown = const Duration(milliseconds: 1200),
  });

  final double threshold; // m/s²
  final int minPeaks;
  final Duration window;
  final Duration cooldown;

  final List<DateTime> _peaks = [];
  DateTime? _lastShake;

  /// Feeds one sample; returns true when a shake is recognised.
  bool add(double x, double y, double z, DateTime time) {
    if (sqrt(x * x + y * y + z * z) < threshold) return false;
    if (_lastShake != null && time.difference(_lastShake!) < cooldown) {
      return false;
    }
    _peaks
      ..add(time)
      ..removeWhere((t) => time.difference(t) > window);
    if (_peaks.length >= minPeaks) {
      _peaks.clear();
      _lastShake = time;
      return true;
    }
    return false;
  }

  /// No sensor plugin in widget tests.
  static final bool _testing =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Listens to the device sensor and calls [onShake]. Returns null when the
  /// device has no such sensor (e.g. in tests or emulators).
  static StreamSubscription<UserAccelerometerEvent>? listen(
    void Function() onShake,
  ) {
    if (_testing) return null;
    final detector = ShakeDetector();
    try {
      return userAccelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (e) {
          if (detector.add(e.x, e.y, e.z, DateTime.now())) onShake();
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {
      return null;
    }
  }
}
