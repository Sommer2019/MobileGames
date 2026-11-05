import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/leaderboard.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_logic.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('after the fixed levels the endless ones are listed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final last = labyrinthLevels.length - 1;
    SharedPreferences.setMockInitialValues({
      'labyrinth.best.$last': 12.5,
      // Two endless ones already done.
      'labyrinth.best.${last + 1}': 30.0,
      'labyrinth.best.${last + 2}': 31.0,
    });
    await tester.pumpWidget(const MaterialApp(home: LabyrinthLevelsScreen()));
    await tester.pumpAndSettle();
    final next = find.byKey(ValueKey('labyrinthLevel${last + 3}'));
    await tester.scrollUntilVisible(next, 400);
    expect(find.text('♾️ Endlos'), findsOneWidget);
    expect(find.text('Endlos 3 · Irrgarten'), findsOneWidget);
    // Shown: the two done, the one to play and a few ahead.
    expect(find.byKey(ValueKey('labyrinthLevel${last + 5}')), findsOneWidget);
    expect(tester.widget<ListTile>(next).enabled, isTrue);
    expect(
      tester
          .widget<ListTile>(find.byKey(ValueKey('labyrinthLevel${last + 4}')))
          .enabled,
      isFalse,
    );
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Endlos 3'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  test('the leaderboard counts endless levels too', () async {
    SharedPreferences.setMockInitialValues({
      'labyrinth.best.0': 1.0,
      'labyrinth.best.40': 2.0,
      'labyrinth.bestx': 3.0,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(solvedLevels(prefs, 'labyrinth.best.'), {0, 40});
    expect(boardById('labyrinth').plausible(300), isTrue);
  });
}
