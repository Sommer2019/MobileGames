import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/domino/domino_logic.dart';

void main() {
  test('set has 28 tiles and deal sizes', () {
    expect(Domino.tiles.length, 28);
    final m = DominoMatch(players: 2)..apply(['deal', 1]);
    expect(m.hands.map((h) => h.length), [7, 7]);
    expect(m.boneyard.length, 14);
    final m4 = DominoMatch(players: 4)..apply(['deal', 1]);
    expect(m4.hands.map((h) => h.length), [5, 5, 5, 5]);
  });

  test('tiles must match the ends', () {
    final m = DominoMatch(players: 2)..apply(['deal', 7]);
    final t = m.hands[0].first;
    expect(m.apply(['play', t, 1]), isTrue);
    final (a, b) = Domino.tiles[t];
    for (final x in m.hands[1]) {
      final (c, d) = Domino.tiles[x];
      final fits = c == a || d == a || c == b || d == b;
      expect(m.sidesFor(x).isNotEmpty, fits);
      if (!fits) expect(m.apply(['play', x, 0]), isFalse);
    }
    expect(m.apply(['draw']), m.playable().isEmpty);
  });

  test('computer matches run to the end and replay identically', () {
    final rnd = Random(3);
    for (final n in [2, 3, 4]) {
      final m = DominoMatch(players: n);
      var guard = 0;
      while (!m.isOver && guard++ < 5000) {
        if (m.roundOver) {
          expect(m.apply(['deal', rnd.nextInt(1 << 30)]), isTrue);
        } else {
          expect(m.apply(DominoAi.choose(m)), isTrue);
          final (l, r) = (m.left, m.right);
          for (var i = 0; i + 1 < m.line.length; i++) {
            expect(m.line[i].b, m.line[i + 1].a);
          }
          expect(l, m.line.first.a);
          expect(r, m.line.last.b);
        }
      }
      expect(m.isOver, isTrue);
      expect(m.scores[m.winner!], greaterThanOrEqualTo(100));
      final copy = DominoMatch.replay(n, m.events);
      expect(copy.scores, m.scores);
      // Rematch starts a new match with fresh scores.
      expect(m.apply(['deal', 5]), isTrue);
      expect(m.scores.every((s) => s == 0), isTrue);
    }
  });
}
