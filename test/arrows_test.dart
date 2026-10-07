import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/arrows/arrows_logic.dart';

void main() {
  test('levels are deterministic, valid and always solvable', () {
    for (final (n, d) in [
      for (final d in ArrowsDifficulty.values)
        for (final n in [1, 37, 257]) (n, d),
    ]) {
      final level = ArrowsLevel.generate(n, d);
      final again = ArrowsLevel.generate(n, d);
      expect(again.arrows.length, level.arrows.length);
      expect(level.arrows.length, greaterThan(3));
      final seen = <(int, int)>{};
      for (final a in level.arrows) {
        expect(a.cells.length, greaterThanOrEqualTo(2));
        expect(a.dir, isNot(-1));
        for (var k = 0; k + 1 < a.cells.length; k++) {
          final (x1, y1) = a.cells[k];
          final (x2, y2) = a.cells[k + 1];
          expect((x1 - x2).abs() + (y1 - y2).abs(), 1);
        }
        for (final c in a.cells) {
          expect(level.inside(c.$1, c.$2), isTrue);
          expect(seen.add(c), isTrue, reason: 'cells overlap in level $n');
        }
      }
      // Greedy: always remove any free arrow – must clear the board.
      final g = ArrowsGame(level);
      while (!g.won) {
        final h = g.hint();
        expect(h, isNotNull, reason: 'level $n got stuck');
        expect(g.tap(h!), isTrue);
      }
      expect(g.hearts, 3);
    }
  });

  test('a blocked arrow costs a heart and stays', () {
    // Arrow 0 points right into arrow 1.
    final level = ArrowsLevel(5, 1, [
      Arrow([(0, 0), (1, 0)]),
      Arrow([(3, 0), (4, 0)]),
    ]);
    final g = ArrowsGame(level);
    expect(g.wayOut(0), (1, 1));
    expect(g.tap(0), isFalse);
    expect(g.hearts, 2);
    expect(g.tap(1), isTrue);
    expect(g.tap(0), isTrue);
    expect(g.won, isTrue);
  });
}
