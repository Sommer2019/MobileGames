import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/sudoku/sudoku_logic.dart';

void main() {
  test('puzzles: unique solution, about the wanted givens, same seed same '
      'puzzle', () {
    final watch = Stopwatch()..start();
    for (final level in SudokuLevel.values) {
      for (var n = 0; n < 4; n++) {
        final p = SudokuPuzzle.generate('anna:sudoku-$n', level);
        final shown = p.givens.where((v) => v != 0).length;
        expect(
          shown,
          inInclusiveRange(level.givens, level.givens + 6),
          reason: '${level.name} $n',
        );
        expect(countSolutions(p.givens), 1);
        final sol = List.filled(81, 0);
        countSolutions(p.givens, solution: sol);
        expect(sol, p.solution);
        final again = SudokuPuzzle.generate('anna:sudoku-$n', level);
        expect(again.givens, p.givens);
      }
    }
    expect(
      SudokuPuzzle.generate('a:1', SudokuLevel.easy).givens,
      isNot(SudokuPuzzle.generate('b:1', SudokuLevel.easy).givens),
    );
    // ignore: avoid_print
    print('12 puzzles in ${watch.elapsedMilliseconds} ms');
  });

  test('entering, notes, clashes, undo, solved', () {
    final g = SudokuGame(SudokuPuzzle.generate('x:1', SudokuLevel.easy));
    final empty = [
      for (var i = 0; i < 81; i++)
        if (!g.isGiven(i)) i,
    ];
    final given = List.generate(81, (i) => i).firstWhere(g.isGiven);
    expect(g.set(given, 5), isFalse, reason: 'given cells stay');
    final a = empty.first;
    final wrong = g.puzzle.solution[a] % 9 + 1;
    // A peer of a with the wrong number in its row would clash.
    expect(g.toggleNote(a, 3), isTrue);
    expect(g.notes[a], 1 << 3);
    g.set(a, wrong);
    expect(g.notes[a], 0, reason: 'a number replaces the notes');
    expect(g.undo(), isTrue);
    expect(g.cells[a], 0);
    expect(g.notes[a], 1 << 3);
    for (final i in empty) {
      g.set(i, g.puzzle.solution[i]);
    }
    expect(g.solved, isTrue);
    expect(empty.any(g.clashes), isFalse);
  });

  test('a solved game proves its time, changes are caught', () {
    final g = SudokuGame(
      SudokuPuzzle.generate(
        sudokuSeed('anna', SudokuLevel.medium, 3),
        SudokuLevel.medium,
      ),
    );
    for (var i = 0; i < 81; i++) {
      if (!g.isGiven(i)) g.set(i, g.puzzle.solution[i]);
    }
    final proof = SudokuProof.of(g, 400);
    expect(SudokuProof.verify('sudoku.medium', proof, 'anna'), 400);
    expect(SudokuProof.verify('sudoku.medium', proof, 'ben'), isNull);
    expect(SudokuProof.verify('sudoku.hard', proof, 'anna'), isNull);
    // Too fast for the number of entries.
    expect(
      SudokuProof.verify('sudoku.medium', {...proof, 't': 3}, 'anna'),
      isNull,
    );
    // Not solved.
    final half = {...proof, 'm': (proof['m'] as List).take(10).toList()};
    expect(SudokuProof.verify('sudoku.medium', half, 'anna'), isNull);
    expect(formatClock(245), '4:05');
    expect(formatClock(3723), '1:02:03');
  });
}
