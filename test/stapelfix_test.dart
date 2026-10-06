import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/stapelfix/stapelfix_logic.dart';

void main() {
  int total(StapelfixGame g) =>
      g.pile.length +
      g.done.length +
      g.build.fold<int>(0, (s, b) => s + b.length) +
      [for (var p = 0; p < g.players; p++) p].fold<int>(
        0,
        (s, p) =>
            s +
            g.stock[p].length +
            g.hands[p].length +
            g.discards[p].fold<int>(0, (t, d) => t + d.length),
      );

  test('deal and building rules', () {
    final g = StapelfixGame(players: 2)..apply(['deal', 9, 18]);
    expect(g.stock.map((s) => s.length), [20, 20]);
    expect(g.hands[g.current].length, 5);
    expect(total(g), 162);
    // Only a 1 or a joker starts a pile.
    for (final c in g.hands[g.current]) {
      final ok = StapelfixGame.isJoker(c) || StapelfixGame.value(c) == 1;
      expect(g.canBuild(c, 0), ok);
    }
    // Discarding ends the turn and fills the next hand.
    final c = g.hands[g.current].first;
    final before = g.current;
    expect(g.apply(['x', c, 0]), isTrue);
    expect(g.current, 1 - before);
    expect(g.hands[g.current].length, 5);
    expect(g.discardTop(before, 0), c);
  });

  test('computer games end with a winner and replay identically', () {
    for (final n in [2, 3, 4, 6]) {
      for (final jokers in [18, 36]) {
        final g = StapelfixGame(players: n)..apply(['deal', n * 31, jokers]);
        final ai = StapelfixAi();
        var guard = 0;
        while (!g.isOver && guard++ < 20000) {
          expect(g.apply(ai.choose(g)), isTrue);
          expect(total(g), 144 + jokers);
        }
        expect(g.isOver, isTrue, reason: '$n players, $jokers jokers');
        expect(g.stock[g.winner!], isEmpty);
        final copy = StapelfixGame.replay(n, g.events);
        expect(copy.winner, g.winner);
      }
    }
  });
}
