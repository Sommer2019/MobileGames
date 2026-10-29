import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/snake/snake_logic.dart';

void main() {
  test('moves, cannot reverse, dies at the wall', () {
    final g = SnakeGame(width: 10, height: 10, random: Random(1));
    g.food = (0, 0);
    final head = g.body.first;
    g.step();
    expect(g.body.first, (head.$1, head.$2 - 1));
    g.turn(Dir.down); // reverse is ignored
    g.step();
    expect(g.direction, Dir.up);
    for (var i = 0; i < 10; i++) {
      g.step();
    }
    expect(g.dead, isTrue);
  });

  test('eating grows the snake and increases speed', () {
    final g = SnakeGame(width: 10, height: 10, random: Random(2));
    final (x, y) = g.body.first;
    g.food = (x, y - 1);
    final len = g.body.length;
    final speed = g.speed;
    g.step();
    expect(g.body.length, len + 1);
    expect(g.score, 1);
    expect(g.speed, greaterThan(speed));
    expect(g.body.contains(g.food), isFalse);
  });

  test('biting itself is fatal, wrap mode passes through walls', () {
    final g = SnakeGame(width: 10, height: 10, random: Random(3));
    g.body
      ..clear()
      ..addAll([(5, 5), (5, 6), (6, 6), (6, 5), (6, 4)]);
    g.food = (0, 0);
    g.direction = Dir.up;
    g.turn(Dir.right);
    g.step();
    expect(g.dead, isTrue);

    final w = SnakeGame(width: 10, height: 10, wrap: true, random: Random(4));
    w.food = (9, 9);
    for (var i = 0; i < 12; i++) {
      w.step();
    }
    expect(w.dead, isFalse);
  });

  test('two quick swipes within one step both count', () {
    final g = SnakeGame(width: 10, height: 10, random: Random(5));
    g.food = (0, 0);
    final (x, y) = g.body.first;
    // U-turn: left, then down before the next step.
    g.turn(Dir.left);
    g.turn(Dir.down);
    g.step();
    expect(g.body.first, (x - 1, y));
    g.step();
    expect(g.body.first, (x - 1, y + 1));
    expect(g.dead, isFalse);
    // A reversal of the last queued turn is ignored.
    g.turn(Dir.right);
    g.turn(Dir.left);
    g.step();
    expect(g.direction, Dir.right);
  });

  test('a won game (board full) counts as finished and verifies', () {
    final key = 'ab' * 32;
    final g = SnakeGame(seed: '$key:1');
    // Follows a cycle through every cell: up column 0, zigzag the rest.
    (int, int) next(int x, int y) {
      if (x == 0) return y == 0 ? (1, 0) : (0, y - 1);
      if (y.isEven) return x < 19 ? (x + 1, y) : (19, y + 1);
      if (x > 1) return (x - 1, y);
      return y < 27 ? (1, y + 1) : (0, 27);
    }

    while (!g.over) {
      final (x, y) = g.body.first;
      final (nx, ny) = next(x, y);
      final d = Dir.values.firstWhere((d) => d.delta == (nx - x, ny - y));
      if (d != g.direction) g.turn(d);
      g.step();
    }
    expect(g.won, isTrue);
    expect(g.dead, isFalse);
    expect(SnakeProof.verify(SnakeProof.of(g), key), 20 * 28 - 3);
  });
}
