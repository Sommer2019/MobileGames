import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/lastcard/lastcard_logic.dart';

void main() {
  test('deck composition', () {
    final kinds = List.filled(15, 0);
    for (var i = 0; i < LcCard.count; i++) {
      kinds[LcCard.kind(i)]++;
    }
    expect(kinds[0], 4);
    for (var k = 1; k <= 9; k++) {
      expect(kinds[k], 8);
    }
    expect(kinds.sublist(10), [8, 8, 8, 4, 4]);
  });

  test('deal, matching and drawing', () {
    final g = LastCardGame(players: 3)..apply(['deal', 11, false]);
    expect(g.hands.every((h) => h.length == 7), isTrue);
    expect(LcCard.kind(g.top), lessThanOrEqualTo(9));
    for (final c in g.hands[0]) {
      final ok =
          LcCard.isWild(c) ||
          LcCard.color(c) == g.color ||
          LcCard.kind(c) == LcCard.kind(g.top);
      expect(g.canPlay(c), ok);
    }
    // Card counts never change in total.
    int total() =>
        g.pile.length +
        g.discard.length +
        g.hands.fold(0, (s, h) => s + h.length);
    expect(total(), 108);
    expect(g.apply(['keep']), isFalse);
    expect(g.apply(['draw']), isTrue);
    expect(total(), 108);
  });

  test('forgetting the call costs two cards', () {
    // Build a position: seat 0 holds two playable cards.
    final g = LastCardGame(players: 2)..apply(['deal', 3, false]);
    final red = [for (var i = 1; i < 25; i++) i];
    g.hands[0]
      ..clear()
      ..addAll([red[0], red[1]]);
    g.color = 0;
    expect(g.canCall, isTrue);
    expect(g.apply(['play', red[0], -1]), isTrue);
    expect(g.hands[0].length, 3);
    expect(g.penalized, 0);
  });

  test('computer games end with a winner and replay identically', () {
    final rnd = Random(5);
    for (final n in [2, 3, 4, 6]) {
      for (final stack in [false, true]) {
        final g = LastCardGame(players: n);
        final ai = LastCardAi(Random(n));
        expect(g.apply(['deal', rnd.nextInt(1 << 30), stack]), isTrue);
        var guard = 0;
        while (!g.isOver && guard++ < 5000) {
          expect(g.apply(ai.choose(g)), isTrue);
        }
        expect(g.isOver, isTrue);
        final copy = LastCardGame.replay(n, g.events);
        expect(copy.winner, g.winner);
        expect(copy.hands, g.hands);
      }
    }
  });
}
