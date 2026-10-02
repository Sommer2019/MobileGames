import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/shake.dart';

void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('three strong movements in a short time are a shake', () {
    final d = ShakeDetector();
    expect(d.add(15, 0, 0, at(0)), isFalse);
    expect(d.add(-15, 0, 0, at(150)), isFalse);
    expect(d.add(15, 2, 0, at(300)), isTrue);
  });

  test('gentle movement and single bumps are ignored', () {
    final d = ShakeDetector();
    for (var i = 0; i < 50; i++) {
      expect(d.add(3, 4, 2, at(i * 20)), isFalse);
    }
    expect(d.add(20, 0, 0, at(2000)), isFalse);
    expect(d.add(20, 0, 0, at(3000)), isFalse, reason: 'too far apart');
    expect(d.add(20, 0, 0, at(4000)), isFalse);
  });

  test('cooldown prevents double rolls', () {
    final d = ShakeDetector();
    d.add(15, 0, 0, at(0));
    d.add(15, 0, 0, at(100));
    expect(d.add(15, 0, 0, at(200)), isTrue);
    expect(d.add(15, 0, 0, at(300)), isFalse);
    expect(d.add(15, 0, 0, at(400)), isFalse);
    expect(d.add(15, 0, 0, at(500)), isFalse);
    d.add(15, 0, 0, at(1500));
    d.add(15, 0, 0, at(1600));
    expect(d.add(15, 0, 0, at(1700)), isTrue);
  });
}
