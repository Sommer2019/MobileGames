import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/schocken/schocken_logic.dart';

/// Plays one turn: rolls [dice] (all free) and stops unless the roll
/// already ended the turn.
void turn(SchockenGame g, List<int> dice) {
  expect(g.apply(['r', ...dice]), isTrue);
  if (g.rolls > 0 && !g.isOver) expect(g.apply(['s']), isTrue);
}

SchockenGame started(int players) =>
    SchockenGame(players: players)..apply(['new']);

void main() {
  test('throws rank from Schock aus down to plain numbers', () {
    int s(List<int> d) => SchockenThrow(d).score;
    expect(s([1, 1, 1]), greaterThan(s([1, 6, 1])));
    expect(s([1, 6, 1]), greaterThan(s([1, 1, 2])));
    expect(s([1, 1, 2]), greaterThan(s([6, 6, 6])));
    expect(s([2, 2, 2]), greaterThan(s([4, 5, 6])));
    expect(s([1, 2, 3]), greaterThan(s([6, 6, 5])));
    expect(s([6, 4, 2]), 642);
    expect(SchockenThrow([1, 1, 5]).name, 'Schock 5');
    expect(SchockenThrow([5, 3, 4]).name, 'Straße 3-4-5');
    expect(SchockenThrow([1, 1, 4]).lids, 4);
    expect(SchockenThrow([3, 3, 3]).lids, 3);
    expect(SchockenThrow([2, 3, 4]).lids, 2);
    expect(SchockenThrow([6, 5, 3]).lids, 1);
  });

  test('the first player sets how often the others may throw', () {
    final g = started(3);
    expect(g.current, 0);
    g.apply(['r', 2, 3, 5]);
    g.apply(['r', 2, 3, 5]);
    g.apply(['s']);
    expect(g.maxRolls, 2);
    expect(g.current, 1);
    g.apply(['r', 6, 6, 4]);
    g.apply(['r', 6, 6, 4]);
    // The second throw used up the limit: the turn is over.
    expect(g.current, 2);
    expect(g.results[1].rolls, 2);
  });

  test('kept dice stay, two sixes turn into a one', () {
    final g = started(2);
    g.apply(['r', 6, 6, 3]);
    expect(g.apply(['t']), isTrue);
    expect(g.dice.where((d) => d == 1), hasLength(1));
    expect(g.held.where((h) => h), hasLength(1));
    final kept = g.held.indexOf(true);
    final wrong = List.of(g.dice)..[kept] = 4;
    expect(g.apply(['r', ...wrong]), isFalse);
    expect(g.apply(['h', kept]), isTrue);
    expect(g.apply(['r', 5, 5, 5]), isTrue);
  });

  test('the worst throw takes lids from the pot, the loser starts next', () {
    final g = started(2);
    turn(g, [1, 1, 4]); // Schock 4
    turn(g, [6, 5, 3]);
    expect(g.lids, [0, 4]);
    expect(g.pot, 9);
    // The loser starts the next round.
    expect(g.current, 1);
    turn(g, [2, 3, 4]);
    turn(g, [2, 2, 2]); // General beats the street: seat 1 loses again.
    expect(g.lids, [0, 7]);
    expect(g.pot, 6);
  });

  test('equal throws: fewer throws win, then who threw first', () {
    final g = started(2);
    turn(g, [6, 5, 2]);
    turn(g, [6, 5, 2]);
    expect(g.lastRound!.worst, 1);
    g.apply(['r', 3, 2, 1]);
    g.apply(['r', 6, 5, 2]);
    g.apply(['s']);
    turn(g, [6, 5, 2]);
    expect(g.lastRound!.worst, 1, reason: 'seat 1 started with two throws');
  });

  test('Schock aus loses the half, two different losers play the final', () {
    final g = started(3);
    turn(g, [1, 1, 1]);
    turn(g, [6, 5, 3]);
    turn(g, [6, 5, 4]);
    expect(g.half, 2);
    expect(g.halfLosers, [1]);
    expect(g.pot, 13);
    expect(g.current, 1, reason: 'the loser of the half starts');
    turn(g, [6, 5, 4]);
    turn(g, [6, 5, 3]);
    turn(g, [1, 1, 1]);
    expect(g.halfLosers, [1, 2]);
    expect(g.half, 3);
    expect(g.inHalf, [false, true, true]);
    expect(g.order, [2, 1]);
    turn(g, [1, 1, 1]);
    turn(g, [2, 3, 5]);
    expect(g.isOver, isTrue);
    expect(g.loser, 1);
  });

  test('losing both halves loses the game', () {
    final g = started(2);
    turn(g, [1, 1, 1]);
    turn(g, [2, 3, 5]);
    expect(g.halfLosers, [1]);
    turn(g, [2, 3, 5]);
    turn(g, [1, 1, 1]);
    expect(g.loser, 1);
    expect(g.apply(['r', 1, 2, 3]), isFalse);
    expect(g.apply(['new']), isTrue);
    expect(g.isOver, isFalse);
  });

  test('all 13 lids lose the half', () {
    final g = started(3);
    for (var i = 0; i < 13; i++) {
      for (var k = 0; k < 3; k++) {
        turn(g, g.current == 1 ? [6, 4, 2] : [6, 5, 3]);
      }
    }
    expect(g.halfLosers, [1]);
    expect(g.half, 2);
  });

  test('players without lids are out once the pot is empty', () {
    final g = started(3);
    turn(g, [1, 1, 6]); // 6 lids for seat 2.
    turn(g, [6, 5, 4]);
    turn(g, [6, 5, 3]);
    turn(g, [6, 5, 3]); // seat 2 starts
    turn(g, [1, 1, 6]);
    turn(g, [6, 5, 4]);
    expect(g.lids, [0, 0, 12]);
    expect(g.pot, 1);
    turn(g, [1, 1, 6]); // seat 2
    turn(g, [6, 5, 3]);
    turn(g, [6, 5, 4]);
    expect(g.pot, 0);
    expect(g.lids, [1, 0, 12]);
    expect(g.active, [true, false, true]);
    expect(g.order, [0, 2]);
    // Now the lids come from the best player.
    turn(g, [1, 1, 3]);
    turn(g, [6, 5, 4]);
    expect(g.halfLosers, [2]);
  });

  test('replaying the events gives the same game', () {
    final rnd = Random(4);
    final ai = SchockenAi();
    final g = started(4);
    for (var i = 0; i < 3000 && !g.isOver; i++) {
      expect(g.apply(ai.choose(g, rnd)), isTrue);
    }
    expect(g.isOver, isTrue);
    final r = SchockenGame.replay(4, g.events);
    expect(r.loser, g.loser);
    expect(r.halfLosers, g.halfLosers);
  });
}
