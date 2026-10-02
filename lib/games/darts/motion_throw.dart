import 'dart:math';

/// Turns phone movement into a dart throw.
///
/// The phone is held next to the cheek. At calibration the current
/// orientation counts as "aiming at the bull". Turning left/right (rotation
/// around the vertical axis) moves the aim sideways, tilting moves it up and
/// down. A strong forward swing throws; the aim from just before the swing
/// is used, because the swing itself rotates the phone.
class MotionAim {
  MotionAim({
    this.mmPerDegree = 9,
    this.throwThreshold = 16,
    this.startThreshold = 6,
    this.invertX = false,
    this.invertY = false,
  });

  /// How far the aim moves on the board per degree of rotation.
  final double mmPerDegree;

  /// Linear acceleration (m/s²) that counts as a throw.
  final double throwThreshold;

  /// Acceleration where a swing starts (aim is frozen there).
  final double startThreshold;
  bool invertX;
  bool invertY;

  // Unit vector pointing up in device coordinates (from gravity) and the
  // horizontal axis used for tilting (screen normal made horizontal).
  List<double> _up = const [0, 1, 0];
  List<double> _tiltAxis = const [0, 0, 1];
  double _yaw = 0, _pitch = 0; // radians since calibration
  bool calibrated = false;

  final List<(Duration, double, double)> _history = [];
  Duration _now = Duration.zero;
  Duration? _swingStart;
  double _peak = 0;
  Duration? _peakAt;

  /// Current aim on the board in millimetres (x right, y down).
  (double, double) get aim {
    final deg = 180 / pi;
    final x = -_yaw * deg * mmPerDegree * (invertX ? -1 : 1);
    final y = -_pitch * deg * mmPerDegree * (invertY ? -1 : 1);
    return (x, y);
  }

  /// Starts aiming. [gravity] is a raw accelerometer reading (device axes)
  /// while the phone is held still.
  void calibrate(double gx, double gy, double gz) {
    final len = sqrt(gx * gx + gy * gy + gz * gz);
    if (len < 1e-6) return;
    _up = [gx / len, gy / len, gz / len];
    // Screen normal (device z) projected onto the horizontal plane.
    final dot = _up[2];
    var t = [-dot * _up[0], -dot * _up[1], 1 - dot * _up[2]];
    final tl = sqrt(t[0] * t[0] + t[1] * t[1] + t[2] * t[2]);
    if (tl < 0.2) {
      // Phone lies flat: use the device x axis instead.
      final d = _up[0];
      t = [1 - d * _up[0], -d * _up[1], -d * _up[2]];
    }
    final n = sqrt(t[0] * t[0] + t[1] * t[1] + t[2] * t[2]);
    _tiltAxis = [t[0] / n, t[1] / n, t[2] / n];
    _yaw = 0;
    _pitch = 0;
    _history.clear();
    _swingStart = null;
    _peak = 0;
    _peakAt = null;
    calibrated = true;
  }

  /// Gyroscope sample (rad/s, device axes) covering [dt] seconds.
  void addGyro(double wx, double wy, double wz, double dt) {
    if (!calibrated) return;
    _now += Duration(microseconds: (dt * 1e6).round());
    if (_swingStart == null) {
      _yaw += (wx * _up[0] + wy * _up[1] + wz * _up[2]) * dt;
      _pitch +=
          (wx * _tiltAxis[0] + wy * _tiltAxis[1] + wz * _tiltAxis[2]) * dt;
    }
    final (x, y) = aim;
    _history.add((_now, x, y));
    if (_history.length > 300) _history.removeAt(0);
  }

  /// Linear acceleration sample (gravity removed). Returns a throw when the
  /// swing peaked: (aim x, aim y, strength in m/s²).
  (double, double, double)? addAcceleration(double ax, double ay, double az) {
    if (!calibrated) return null;
    final a = sqrt(ax * ax + ay * ay + az * az);
    if (_swingStart == null && a >= startThreshold) _swingStart = _now;
    if (_swingStart != null &&
        a < startThreshold * 0.5 &&
        _peak < throwThreshold) {
      // Just a wobble, not a throw.
      _swingStart = null;
      _peak = 0;
    }
    if (a > _peak) {
      _peak = a;
      _peakAt = _now;
    }
    final peakAt = _peakAt;
    // A throw: strong enough, and the acceleration has dropped again.
    if (_peak >= throwThreshold && peakAt != null && a < _peak * 0.6) {
      final (x, y) = _aimAt(_swingStart ?? peakAt);
      final strength = _peak;
      calibrated = false;
      return (x, y, strength);
    }
    return null;
  }

  (double, double) _aimAt(Duration t) {
    for (final (time, x, y) in _history.reversed) {
      if (time <= t) return (x, y);
    }
    return aim;
  }

  /// Turns the swing strength into a vertical error: a weak throw drops
  /// low, an overly hard one flies high. ~22 m/s² is ideal.
  static double heightError(double strength) =>
      ((22 - strength) * 3.5).clamp(-60.0, 90.0);
}
