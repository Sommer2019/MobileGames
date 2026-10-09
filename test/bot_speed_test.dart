import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/boxes/boxes_screen.dart';
import 'package:mobile_games/games/chess/chess_screen.dart';
import 'package:mobile_games/ui/bot_speed.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('fast-forward only where a computer plays, normal by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChessScreen(setup: PlaySetup.local())),
    );
    expect(find.byKey(const ValueKey('fastForward')), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: BoxesScreen(setup: PlaySetup.local(players: 2, bots: {0, 1})),
      ),
    );
    expect(BotSpeed.fast.value, isFalse);
    expect(BotSpeed.ms(700), const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const ValueKey('fastForward')));
    await tester.pump();
    expect(BotSpeed.fast.value, isTrue);
    expect(BotSpeed.ms(600), const Duration(milliseconds: 100));
    // Computers move much quicker now: many lines in a short time.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('fastForward')));
    await tester.pump();
    expect(BotSpeed.fast.value, isFalse);
    // Leaving the game resets it.
    await tester.tap(find.byKey(const ValueKey('fastForward')));
    await tester.pumpWidget(const SizedBox());
    expect(BotSpeed.fast.value, isFalse);
    await tester.pump(const Duration(seconds: 2));
  });
}
