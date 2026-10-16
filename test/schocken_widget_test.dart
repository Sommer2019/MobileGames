import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/registry.dart';
import 'package:mobile_games/games/rules.dart';
import 'package:mobile_games/games/schocken/schocken_screen.dart';
import 'package:mobile_games/ui/home_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Schocken: throwing, stopping, the computer follows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: SchockenScreen(setup: PlaySetup.local(players: 2, bots: {1})),
      ),
    );
    var turns = 0;
    for (var i = 0; i < 400 && turns < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.textContaining('Du bist dran').evaluate().isEmpty) continue;
      turns++;
      await tester.tap(find.byKey(const ValueKey('schockenRoll')));
      await tester.pump();
      expect(find.byKey(const ValueKey('schockenThrow')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schockenStop')));
      await tester.pump();
      // The next player (maybe again us after losing) has not thrown yet.
      expect(find.byKey(const ValueKey('schockenThrow')), findsNothing);
    }
    expect(turns, 3);
    expect(find.byKey(const ValueKey('schockenPot')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  test('every game has rules', () {
    for (final g in games) {
      expect(gameRules[g.id], isNotNull, reason: g.title);
    }
    expect(gameRules.keys.toSet(), {for (final g in games) g.id});
  });

  testWidgets('the i on a game shows its rules', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    final i = find.byKey(const ValueKey('rules-schocken'));
    await tester.scrollUntilVisible(i, 300);
    await tester.tap(i);
    await tester.pumpAndSettle();
    expect(find.text('Regeln: Schocken'), findsOneWidget);
    expect(find.textContaining('Schock aus'), findsWidgets);
  });
}
