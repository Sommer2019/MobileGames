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
}
