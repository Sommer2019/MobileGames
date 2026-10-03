import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/konami.dart';
import 'package:mobile_games/core/secrets.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the full sequence unlocks, wrong inputs reset', () {
    final k = KonamiCode();
    for (final i in KonamiCode.sequence.take(10)) {
      expect(k.add(i), isFalse);
    }
    expect(k.add(KonamiInput.plugIn), isTrue);

    // A mistake starts over.
    for (final i in KonamiCode.sequence.take(5)) {
      k.add(i);
    }
    k.add(KonamiInput.volumeUp);
    expect(k.progress, 0);

    // ↑ ↑ ↑ ↓ ↓ … still works.
    final k2 = KonamiCode();
    k2.add(KonamiInput.up);
    for (final i in KonamiCode.sequence) {
      final done = k2.add(i);
      expect(done, i == KonamiInput.plugIn);
    }
  });

  test('pressing a volume button twice is fine', () {
    final k = KonamiCode();
    for (final i in KonamiCode.sequence.take(8)) {
      k.add(i);
    }
    k.add(KonamiInput.volumeUp);
    k.add(KonamiInput.volumeUp);
    k.add(KonamiInput.volumeDown);
    k.add(KonamiInput.volumeDown);
    expect(k.add(KonamiInput.plugIn), isTrue);
  });

  test('jingle: pauses and vibrations alternate, all have a strength', () {
    expect(konamiJingle.length, konamiJingleIntensities.length);
    for (var i = 0; i < konamiJingle.length; i++) {
      expect(konamiJingleIntensities[i] == 0, i.isEven);
    }
  });

  test('too slow does not count', () {
    final k = KonamiCode();
    final t0 = DateTime(2026);
    for (final i in KonamiCode.sequence.take(10)) {
      k.add(i, now: t0);
    }
    expect(
      k.add(KonamiInput.plugIn, now: t0.add(const Duration(minutes: 5))),
      isFalse,
    );
  });

  testWidgets('swipes, volume keys and the charger unlock', (tester) async {
    final battery = StreamController<BatteryState>();
    var unlocked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KonamiDetector(
          batteryStates: battery.stream,
          onUnlocked: () => unlocked++,
          child: ListView(
            children: [for (var i = 0; i < 30; i++) Text('Zeile $i')],
          ),
        ),
      ),
    );
    battery.add(BatteryState.discharging);
    await tester.pump();
    final center = tester.getCenter(find.byType(ListView));
    Future<void> swipe(Offset d) async {
      final g = await tester.startGesture(center);
      await g.moveBy(d / 2);
      await g.moveBy(d / 2);
      await g.up();
      await tester.pumpAndSettle();
    }

    const up = Offset(0, -150), down = Offset(0, 150);
    const left = Offset(-150, 0), right = Offset(150, 0);
    for (final d in [up, up, down, down, left, right, left, right]) {
      await swipe(d);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    expect(unlocked, 0);
    battery.add(BatteryState.charging);
    await tester.pump();
    expect(unlocked, 1);
    await battery.close();
  });

  testWidgets('easy mode unlocks all levels in the list', (tester) async {
    SharedPreferences.setMockInitialValues({'labyrinth.cheat': true});
    Secrets.I.reset();
    await Secrets.I.load();
    await tester.pumpWidget(const MaterialApp(home: LabyrinthLevelsScreen()));
    await tester.pumpAndSettle();
    // No switch in the list; easy mode is in the secret menu.
    expect(find.byKey(const ValueKey('cheatSwitch')), findsNothing);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
    expect(tiles.every((t) => t.enabled), isTrue);
  });
}
