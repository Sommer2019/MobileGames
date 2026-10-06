import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/halma/halma_logic.dart';

void main() {
  test('star has 121 holes and six arms of 10', () {
    expect(HalmaBoard.cells.length, 121);
    for (final a in HalmaBoard.arms) {
      expect(a.length, 10);
    }
    for (var a = 0; a < 6; a++) {
      expect(
        HalmaBoard.distance(HalmaBoard.tips[a], HalmaBoard.tips[(a + 3) % 6]),
        16,
      );
    }
  });

  test('steps and jump chains', () {
    final g = HalmaGame(players: 2);
    for (var c = 0; c < g.owner.length; c++) {
      if (g.owner[c] != 0) continue;
      g.destinations(c).forEach((to, path) {
        expect(g.isValid(path), isTrue, reason: '$path');
      });
    }
    // A jump without a piece in between is not allowed.
    final front = HalmaBoard.arms[0].firstWhere(
      (c) => g.destinations(c).isNotEmpty,
    );
    final far = g.destinations(front).keys.first;
    expect(g.isValid([front, far, far]), isFalse);
  });

  test('computer games end with a winner', () {
    for (final n in [2, 3, 4, 6]) {
      final g = HalmaGame(players: n);
      final ai = HalmaAi(Random(n));
      var guard = 0;
      while (!g.isOver && guard++ < 3000) {
        expect(g.move(ai.choose(g)), isTrue);
      }
      expect(g.isOver, isTrue, reason: '$n players, ${g.moves.length} moves');
      expect(HalmaGame.replay(n, g.moves).winner, g.winner);
    }
  });
}
