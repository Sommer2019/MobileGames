import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/ludo/ludo_logic.dart';

void main() {
  test('three tries for a six, then the next player', () {
    final g = LudoGame(players: 2);
    expect(g.triesLeft, 3);
    g.roll(2);
    g.roll(3);
    expect(g.current, 0);
    g.roll(4);
    expect(g.current, 1);
  });

  test('a six must bring a piece out and rolls again', () {
    final g = LudoGame(players: 2);
    g.roll(6);
    expect(g.movable(), [0, 1, 2, 3]);
    expect(g.move(0), isTrue);
    expect(g.pieces[0][0], 0);
    expect(g.current, 0);
    expect(g.mustRoll, isTrue);
    // Start field must be cleared.
    g.roll(3);
    expect(g.movable(), [0]);
    g.move(0);
    expect(g.pieces[0][0], 3);
    expect(g.current, 1);
  });

  test('landing on another piece sends it home', () {
    final g = LudoGame(players: 4);
    g.pieces[0][0] = 8; // field 8
    g.pieces[1][0] = 0; // side 1 start = field 10
    g.pieces[0][1] = 41;
    g.triesLeft = 1;
    g.roll(2);
    expect(g.move(0), isTrue);
    expect(g.pieces[1][0], -1);
    expect(g.lastCapture, (1, 0));
  });

  test('two players sit opposite each other', () {
    final g = LudoGame(players: 2);
    expect(g.absolute(1, 0), 20);
  });

  test('exact count and no jumping in the goal', () {
    final g = LudoGame(players: 2);
    g.pieces[0] = [42, 38, -1, -1];
    g.triesLeft = 1;
    expect(g.target(0, 1, 5), isNull); // would jump over 42
    expect(g.target(0, 1, 3), 41);
    expect(g.target(0, 0, 1), 43);
    expect(g.target(0, 0, 2), isNull);
  });

  test('computer games end with a winner; replay matches', () {
    final r = Random(7);
    final ai = LudoAi(Random(8));
    final g = LudoGame(players: 4);
    var steps = 0;
    while (!g.isOver && steps < 5000) {
      if (g.mustRoll) {
        g.roll(r.nextInt(6) + 1);
      } else {
        g.move(ai.choose(g));
      }
      steps++;
    }
    expect(g.isOver, isTrue);
    expect(g.pieces[g.winner!].every((p) => p >= 40), isTrue);
    final copy = LudoGame.replay(4, g.events);
    expect(copy.winner, g.winner);
    expect(copy.pieces, g.pieces);
  });

  test('the computer prefers capturing', () {
    final g = LudoGame(players: 2);
    g.pieces[0] = [18, 2, -1, -1];
    g.pieces[1][0] = 1; // side 2 position 1 = field 21
    g.triesLeft = 1;
    g.roll(3);
    expect(LudoAi(Random(1)).choose(g), 0);
    g.move(0);
    expect(g.pieces[1][0], -1);
  });
}
