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
