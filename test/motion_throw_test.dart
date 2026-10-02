import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/darts/motion_throw.dart';

void main() {
  test('turning around the vertical axis moves the aim sideways', () {
    final m = MotionAim();
    // Phone upright: gravity reading along +y.
    m.calibrate(0, 9.81, 0);
    expect(m.aim, (0.0, 0.0));
    // Turn right (clockwise seen from above = negative rotation about up).
    for (var i = 0; i < 10; i++) {
      m.addGyro(0, -pi / 180 * 10, 0, 0.1); // 10 deg/s for 1 s
    }
    expect(m.aim.$1, closeTo(90, 1)); // 10° * 9 mm
    expect(m.aim.$2, closeTo(0, 1e-9));
    m.invertX = true;
    expect(m.aim.$1, closeTo(-90, 1));
  });

  test('tilting around the screen normal moves the aim vertically', () {
    final m = MotionAim();
    m.calibrate(0, 9.81, 0);
    for (var i = 0; i < 5; i++) {
      m.addGyro(0, 0, pi / 180 * 10, 0.1); // 5°
    }
    expect(m.aim.$2, closeTo(-45, 1));
    expect(m.aim.$1, closeTo(0, 1e-9));
  });

  test('a swing throws with the aim from before the swing', () {
    final m = MotionAim();
    m.calibrate(0, 9.81, 0);
    for (var i = 0; i < 10; i++) {
      m.addGyro(0, -pi / 180 * 2, 0, 0.05); // aim drifts to 9 mm
    }
    expect(m.addAcceleration(0, 0, 3), isNull, reason: 'wobble');
    expect(m.addAcceleration(0, 0, 8), isNull, reason: 'swing starts');
    // The swing itself rotates the phone a lot; that must not count.
    m.addGyro(0, -pi, 0, 0.05);
    expect(m.addAcceleration(0, 0, 25), isNull, reason: 'still accelerating');
    final t = m.addAcceleration(0, 0, 5);
    expect(t, isNotNull);
    expect(t!.$1, closeTo(9, 1));
    expect(t.$3, 25);
    expect(m.calibrated, isFalse, reason: 'one throw per calibration');
  });

  test('throw strength changes the height', () {
    expect(MotionAim.heightError(22), 0);
    expect(MotionAim.heightError(12), greaterThan(20), reason: 'weak = low');
    expect(MotionAim.heightError(35), lessThan(-20), reason: 'hard = high');
  });
}
