import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/home_widgets.dart';
import 'package:mobile_games/games/dice/dice_cup_screen.dart';
import 'package:mobile_games/games/registry.dart';
import 'package:mobile_games/ui/dice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dice cup: choose the number of dice, tap to roll', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: DiceCupScreen(random: Random(4))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RollingDie), findsNWidgets(2));
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(find.byType(RollingDie), findsNWidgets(5));
    await tester.tap(find.byKey(const ValueKey('diceArea')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final sum = tester.widget<Text>(find.byKey(const ValueKey('diceSum')));
    final n = int.parse(sum.data!.replaceAll(RegExp(r'[^0-9]'), ''));
    expect(n, inInclusiveRange(5, 30));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('dice.count'), 5);
  });

  testWidgets('dice cup: put dice aside, history of the last rolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: DiceCupScreen(random: Random(7))),
    );
    await tester.pumpAndSettle();
    Future<void> roll() async {
      await tester.tapAt(const Offset(400, 900));
      await tester.pumpAndSettle();
    }

    int dieValue(int i) => tester
        .widget<RollingDie>(
          find.descendant(
            of: find.byKey(ValueKey('die$i')),
            matching: find.byType(RollingDie),
          ),
        )
        .value;

    await roll();
    final kept = dieValue(0);
    // Put the first die aside: it moves to the tray and keeps its value.
    await tester.tap(find.byKey(const ValueKey('die0')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('diceAside')),
        matching: find.byKey(const ValueKey('die0')),
      ),
      findsOneWidget,
    );
    for (var i = 0; i < 5; i++) {
      await roll();
      expect(dieValue(0), kept);
    }
    // Both aside: rolling does nothing.
    await tester.tap(find.byKey(const ValueKey('die1')));
    await tester.pumpAndSettle();
    await roll();
    expect(find.text('Alle Würfel liegen beiseite'), findsOneWidget);

    // 6 rolls so far, newest first, persisted.
    expect(find.text('Letzte 6 Würfe'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('dice.history')!;
    expect(saved.split('],').length, 6);

    // At most ten are kept.
    await tester.tap(find.byTooltip('Alle zurücklegen'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await roll();
    }
    expect(find.text('Letzte 10 Würfe'), findsOneWidget);
    await tester.tap(find.byTooltip('Verlauf löschen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('diceHistory')), findsNothing);
  });

  test('widget links point to games', () {
    expect(
      HomeWidgets.linkTarget(Uri.parse('mobilegames://dice?homeWidget')),
      'dice',
    );
    expect(
      HomeWidgets.linkTarget(Uri.parse('mobilegames://game/chess?homeWidget')),
      'chess',
    );
    expect(HomeWidgets.linkTarget(Uri.parse('https://example.com/x')), isNull);
    expect(gameById('dice')?.title, 'Würfelbecher');
  });

  test('recently played games are remembered, newest first, max 3', () async {
    for (final id in ['chess', 'snake', 'dice', 'chess']) {
      await HomeWidgets.recordPlayed(id);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('widget.recent'), ['chess', 'dice', 'snake']);
  });
}
