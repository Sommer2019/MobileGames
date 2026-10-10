import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/prophet/prophet_logic.dart';

/// Colour card [v] (1–13) of colour [c].
int card(int c, int v) => c * 13 + v - 1;
const wizard = 52, wizard2 = 53, fool = 56, fool2 = 57;

void main() {
  test('who takes the trick', () {
    // Highest of the colour led.
    expect(ProphetGame.trickWinner([(0, card(0, 5)), (1, card(0, 9))], -1), 1);
    // Another colour does not win.
    expect(ProphetGame.trickWinner([(0, card(0, 5)), (1, card(1, 13))], -1), 0);
    // Trump beats the colour led.
    expect(ProphetGame.trickWinner([(0, card(0, 13)), (1, card(2, 1))], 2), 1);
    // The first wizard wins.
    expect(
      ProphetGame.trickWinner([(0, card(2, 13)), (1, wizard), (2, wizard2)], 2),
      1,
    );
    // Fools lose, a fool lead lets the next card set the colour.
    expect(
      ProphetGame.trickWinner([
        (0, fool),
        (1, card(1, 3)),
        (2, card(1, 7)),
      ], -1),
      2,
    );
    // Only fools: the first one.
    expect(ProphetGame.trickWinner([(0, fool), (1, fool2)], 0), 0);
  });

  test('colour must be followed, wizards and fools always allowed', () {
    final g = ProphetGame(players: 3);
    g.apply(['deal', 1]);
    // Set up a known situation.
    g
      ..phase = ProphetPhase.playing
      ..current = 1
      ..hands = [
        [card(0, 2)],
        [card(0, 4), card(1, 9), wizard, fool],
        [card(3, 1)],
      ]
      ..trick = [(0, card(0, 2))];
    expect(g.canPlay(card(0, 4)), isTrue);
    expect(g.canPlay(card(1, 9)), isFalse, reason: 'must follow blue');
    expect(g.canPlay(wizard), isTrue);
    expect(g.canPlay(fool), isTrue);
    // After a wizard lead anything goes.
    g.trick = [(0, wizard2)];
    expect(g.canPlay(card(1, 9)), isTrue);
  });

  test('scoring: exact predictions score, others lose points', () {
    final g = ProphetGame(players: 3, first: 0);
    expect(g.rounds, 20);
    g.apply(['deal', 7]);
    expect(g.hands.map((h) => h.length), [1, 1, 1]);
    // Bids start left of the dealer.
    expect(g.phase, isIn([ProphetPhase.bidding, ProphetPhase.trumpChoice]));
    if (g.phase == ProphetPhase.trumpChoice) {
      expect(g.current, g.dealer);
      g.apply(['trump', 0]);
    }
    expect(g.current, 1);
    g.apply(['bid', 0]);
    g.apply(['bid', 1]);
    g.apply(['bid', 0]);
    expect(g.phase, ProphetPhase.playing);
    for (var i = 0; i < 3; i++) {
      g.apply(['play', g.playable().first]);
    }
    expect(g.phase, ProphetPhase.roundOver);
    final w = g.lastWinner!;
    for (var p = 0; p < 3; p++) {
      final bid = [0, 0, 1][p]; // seats 1, 2, 0 bid 0, 1, 0
      final took = p == w ? 1 : 0;
      expect(
        g.scores[p],
        bid == took ? 20 + 10 * took : -10 * (bid - took).abs(),
      );
    }
    // Wrong moves are refused.
    expect(g.apply(['bid', 0]), isFalse);
    expect(g.apply(['deal', 8]), isTrue);
    expect(g.cardsThisRound, 2);
    expect(g.dealer, 1);
  });

  for (final players in [3, 4, 5, 6]) {
    test('$players computers play a whole game', () {
      final ai = ProphetAi(Random(players));
      final rng = Random(99);
      final g = ProphetGame(players: players, first: 1);
      var guard = 0;
      while (!g.isOver && guard++ < 5000) {
        if (g.toMove == null) {
          expect(g.apply(['deal', rng.nextInt(1 << 30)]), isTrue);
          // Every card is used exactly once.
          final all = [...g.hands.expand((h) => h)];
          expect(all.toSet().length, all.length);
          continue;
        }
        expect(g.apply(ai.choose(g)), isTrue);
      }
      expect(g.isOver, isTrue);
      expect(g.history, hasLength(60 ~/ players));
      expect(g.trumpCard, isNull, reason: 'last round: all cards dealt');
      // Replaying the events gives the same result.
      final copy = ProphetGame.replay(players, g.events, first: 1);
      expect(copy.scores, g.scores);
      expect(g.winners(), isNotEmpty);
    });
  }

  test('the computer predicts well against itself', () {
    var exact = 0, total = 0;
    for (var s = 0; s < 20; s++) {
      final g = ProphetGame(players: 4, rounds: 8);
      final ai = ProphetAi(Random(s));
      final rng = Random(s + 100);
      while (!g.isOver) {
        g.apply(
          g.toMove == null ? ['deal', rng.nextInt(1 << 30)] : ai.choose(g),
        );
      }
      for (final r in g.history) {
        exact += r.where((d) => d > 0).length;
        total += r.length;
      }
    }
    // Clearly better than guessing.
    expect(exact / total, greaterThan(0.45));
  });
}
