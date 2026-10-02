import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_logic.dart';

/// Grid search over ball positions: proves a path from start to goal exists
/// that keeps the ball clear of walls and holes.
bool levelSolvable(LabyrinthLevel l) {
  const step = 0.01;
  final w = (boardWidth / step).round(), h = (boardHeight / step).round();
  const r = LabyrinthGame.radius;
  bool free(int i, int j) {
    final x = i * step, y = j * step;
    for (final wall in l.walls) {
      final cx = x.clamp(wall.left, wall.right),
          cy = y.clamp(wall.top, wall.bottom);
      if (pow(x - cx, 2) + pow(y - cy, 2) < r * r) return false;
    }
    for (final hole in l.holes) {
      // Keep a safety margin so the path is realistically playable.
      if (pow(x - hole.x, 2) + pow(y - hole.y, 2) <
          pow(hole.radius + 0.01, 2)) {
        return false;
      }
    }
    return true;
  }

  final start = ((l.start.$1 / step).round(), (l.start.$2 / step).round());
  final seen = <(int, int)>{start};
  final queue = Queue<(int, int)>()..add(start);
  while (queue.isNotEmpty) {
    final (i, j) = queue.removeFirst();
    if (pow(i * step - l.goal.x, 2) + pow(j * step - l.goal.y, 2) <
        pow(l.goal.radius, 2)) {
      return true;
    }
    for (final (di, dj) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final n = (i + di, j + dj);
      if (n.$1 < 0 || n.$2 < 0 || n.$1 > w || n.$2 > h) continue;
      if (seen.contains(n) || !free(n.$1, n.$2)) continue;
      seen.add(n);
      queue.add(n);
    }
  }
  return false;
}

void main() {
  test('there are many levels and later ones are harder', () {
    expect(labyrinthLevels.length, greaterThanOrEqualTo(15));
    final last = labyrinthLevels[16], firstMaze = labyrinthLevels[5];
    expect(last.holes.length, greaterThan(firstMaze.holes.length));
    expect(last.walls.length, greaterThan(firstMaze.walls.length));
    expect(
      labyrinthLevels.map((l) => l.name).toSet().length,
      labyrinthLevels.length,
    );
  });

  test('all levels are solvable', () {
    for (final l in labyrinthLevels) {
      expect(levelSolvable(l), isTrue, reason: l.name);
    }
  });

  test('ball rolls with tilt and stops at walls', () {
    final g = LabyrinthGame(labyrinthLevels.first);
    final x0 = g.x;
    for (var i = 0; i < 300; i++) {
      g.step(1 / 60, 1, 0);
    }
    expect(g.x, greaterThan(x0));
    expect(
      g.x,
      lessThanOrEqualTo(boardWidth - 0.025 - LabyrinthGame.radius + 1e-6),
    );
    expect(g.state, BallState.rolling);
  });

  test('ball never leaves the board, even with violent tilting', () {
    final g = LabyrinthGame(labyrinthLevels.first);
    final rnd = Random(2);
    for (var i = 0; i < 3000 && g.state == BallState.rolling; i++) {
      g.step(1 / 30, rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1);
      expect(g.x, inInclusiveRange(0, boardWidth));
      expect(g.y, inInclusiveRange(0, boardHeight));
    }
  });

  test('without frame the ball falls off the edge', () {
    final l = labyrinthLevels.firstWhere((l) => l.name == 'Ohne Rand');
    expect(l.frame, isFalse);
    final g = LabyrinthGame(l);
    for (var i = 0; i < 300 && g.state == BallState.rolling; i++) {
      g.step(1 / 60, 1, 0);
    }
    expect(g.state, BallState.fell);
    expect(
      labyrinthLevels.where((l) => !l.frame).length,
      greaterThanOrEqualTo(5),
    );
    expect(labyrinthLevels.length, greaterThanOrEqualTo(25));
  });

  test('falling into a hole and reaching the goal', () {
    final l = LabyrinthLevel(
      name: 't',
      start: (0.5, 0.5),
      goal: const Hole(0.5, 0.2),
      walls: const [],
      holes: const [Hole(0.5, 0.8)],
    );
    final down = LabyrinthGame(l);
    for (var i = 0; i < 200; i++) {
      down.step(1 / 60, 0, 1);
    }
    expect(down.state, BallState.fell);
    final up = LabyrinthGame(l);
    for (var i = 0; i < 200; i++) {
      up.step(1 / 60, 0, -1);
    }
    expect(up.state, BallState.won);
    up.reset();
    expect(up.state, BallState.rolling);
    expect(up.y, 0.5);
  });

  test('the ball turns while it rolls', () {
    final g = LabyrinthGame(labyrinthLevels.first);
    final before = g.orientation.qz;
    for (var i = 0; i < 20; i++) {
      g.step(1 / 60, 0.5, 0);
    }
    expect(g.vx, greaterThan(0));
    expect(g.orientation.qz, isNot(closeTo(before, 1e-6)));
    // Rolling to the right moves the top of the ball to the right.
    expect(g.orientation.qx, greaterThan(0));
  });
}
