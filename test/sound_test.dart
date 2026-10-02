import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every sound has its file in the assets', () {
    for (final s in Sfx.values) {
      for (final dir in ['assets/sounds', 'assets/sounds/retro']) {
        final f = File('$dir/${s.name}.wav');
        expect(f.existsSync(), isTrue, reason: f.path);
        expect(f.lengthSync(), greaterThan(500));
      }
    }
  });

  test('sound can be switched off and stays off', () async {
    SharedPreferences.setMockInitialValues({});
    await Sound.load();
    expect(Sound.enabled.value, isTrue);
    await Sound.setEnabled(false);
    Sound.enabled.value = true;
    await Sound.load();
    expect(Sound.enabled.value, isFalse);
    // Playing never throws (no audio plugin in tests).
    Sound.play(Sfx.win);
    await Sound.setEnabled(true);
  });
}
