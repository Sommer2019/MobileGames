import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/leaderboard.dart';
import 'package:mobile_games/games/sudoku/sudoku_logic.dart';
import 'package:mobile_games/games/sudoku/sudoku_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: SudokuScreen()));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('solving one: best time with record, then the next one', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Sudoku Nr. 1'), findsOneWidget);
    final p = SudokuPuzzle.generate(
      sudokuSeed(Leaderboard.proofOwner, SudokuLevel.easy, 1),
      SudokuLevel.easy,
    );
    // Some time passes.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 81; i++) {
      if (p.givens[i] != 0) continue;
      await tester.tap(find.byKey(ValueKey('sudokuCell$i')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('sudokuDigit${p.solution[i]}')));
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gelöst! 🎉'), findsOneWidget);
    final best = await tester.runAsync(
      () => Leaderboard.history('sudoku.easy'),
    );
    expect(best!.single.value, greaterThanOrEqualTo(30));
    expect(
      SudokuProof.verify(
        'sudoku.easy',
        best.single.proof,
        Leaderboard.proofOwner,
      ),
      best.single.value,
    );
    expect(await tester.runAsync(() => Leaderboard.best('sudoku.solved')), 1);
    await tester.tap(find.byKey(const ValueKey('sudokuNext')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sudoku Nr. 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unfinished one goes on after leaving', (tester) async {
    await open(tester);
    final p = SudokuPuzzle.generate(
      sudokuSeed(Leaderboard.proofOwner, SudokuLevel.easy, 1),
      SudokuLevel.easy,
    );
    final i = List.generate(81, (i) => i).firstWhere((i) => p.givens[i] == 0);
    await tester.tap(find.byKey(ValueKey('sudokuCell$i')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sudokuNotes')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sudokuDigit4')));
    await tester.tap(find.byKey(const ValueKey('sudokuNotes')));
    await tester.pump();
    final j = List.generate(81, (k) => k).lastWhere((k) => p.givens[k] == 0);
    await tester.tap(find.byKey(ValueKey('sudokuCell$j')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('sudokuDigit${p.solution[j]}')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await open(tester);
    final cell = find.byKey(ValueKey('sudokuCell$j'));
    expect(
      find.descendant(of: cell, matching: find.text('${p.solution[j]}')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('sudokuCell$i')),
        matching: find.text('4'),
      ),
      findsOneWidget,
      reason: 'notes are kept',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
