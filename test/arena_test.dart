import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/konami.dart';
import 'package:mobile_games/core/secrets.dart';
import 'package:mobile_games/games/registry.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:mobile_games/ui/seat_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Secrets.I.reset();
  });

  test('the code backwards unlocks the Bot-Arena', () async {
    final k = KonamiCode(steps: KonamiCode.arenaSequence);
    final normal = KonamiCode();
    var done = false;
    for (final i in KonamiCode.arenaSequence) {
      expect(normal.add(i), isFalse);
      done = k.add(i);
    }
    expect(done, isTrue);
    expect(Secrets.on(Secret.botArena), isFalse);
    expect(await Secrets.I.unlockArena(), isTrue);
    expect(Secrets.on(Secret.botArena), isTrue);
    // The other secrets still need the real code.
    expect(Secrets.I.unlocked, isFalse);
    expect(Secrets.I.available(Secret.retro), isFalse);
  });

  testWidgets('with the arena the last person can become a computer', (
    tester,
  ) async {
    await Secrets.I.unlockArena();
    final game = games.firstWhere((g) => g.id == 'boxes');
    await tester.pumpWidget(MaterialApp(home: SeatSetupScreen(game: game)));
    await tester.tap(find.byKey(const ValueKey('seat0')));
    await tester.pump();
    expect(find.text('Zuschauen 🤖'), findsOneWidget);
  });

  for (final game in games.where((g) => g.hasBots)) {
    testWidgets('${game.title}: only computers play', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final n = game.playerCounts.contains(3) ? 3 : game.playerCounts.first;
      await tester.pumpWidget(
        MaterialApp(
          home: game.multiplayerBuilder!(
            PlaySetup.local(players: n, bots: {for (var i = 0; i < n; i++) i}),
          ),
        ),
      );
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
