import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/bingo/bingo_logic.dart';

void main() {
  test('cards follow the column ranges and differ per player', () {
    final g = BingoGame(players: 3, seed: 42);
    for (final card in g.cards) {
      expect(card[12], 0);
      expect(card.toSet().length, 25);
      for (var i = 0; i < 25; i++) {
        if (i == 12) continue;
        final col = i % 5;
        expect(card[i], inInclusiveRange(col * 15 + 1, col * 15 + 15));
      }
    }
    expect(g.cards[0], isNot(g.cards[1]));
    expect(BingoGame(players: 3, seed: 42).cards, g.cards);
    expect(g.order.toSet().length, 75);
  });

  test('claims are only accepted with a full line', () {
    final g = BingoGame(players: 2, seed: 7);
    expect(g.claim(0), isFalse);
    while (!g.hasBingo(0) && !g.hasBingo(1)) {
      expect(g.missing(0), greaterThan(0));
      g.draw();
    }
    final w = g.hasBingo(0) ? 0 : 1;
    expect(g.missing(w), 0);
    // Marks must be drawn numbers on the card.
    expect(g.markedBingo(w, {}), isFalse);
    expect(g.markedBingo(w, g.drawnSet), isTrue);
    expect(g.claim(w), isTrue);
    expect(g.claim(1 - w), isFalse);
    expect(g.draw(), isFalse);
  });
}
