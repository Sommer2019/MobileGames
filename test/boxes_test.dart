import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/boxes/boxes_logic.dart';

void main() {
  test('closing a box scores and gives another turn', () {
    final g = BoxesGame(players: 2, size: 2);
    expect(g.lineCount, 12);
    // Box 0: top, bottom, left, right.
    g.draw(g.horizontal(0, 0)); // A
    g.draw(g.horizontal(1, 0)); // B
    g.draw(g.vertical(0, 0)); // A
    expect(g.current, 1);
    g.draw(g.vertical(0, 1)); // B closes box 0
    expect(g.owner[0], 1);
    expect(g.scores, [0, 1]);
    expect(g.current, 1);
  });

  test('one line can close two boxes', () {
    final g = BoxesGame(players: 2, size: 2);
    for (final l in [
      g.horizontal(0, 0),
      g.horizontal(1, 0),
      g.vertical(0, 0),
      g.horizontal(0, 1),
      g.horizontal(1, 1),
      g.vertical(0, 2),
    ]) {
      g.draw(l);
    }
    final p = g.current;
    g.draw(g.vertical(0, 1));
    expect(g.scores[p], 2);
  });

  test('a whole game ends with all boxes owned; replay restores it', () {
    final r = Random(3);
    final g = BoxesGame(players: 3);
    while (!g.isOver) {
      final open = g.openLines;
      g.draw(open[r.nextInt(open.length)]);
    }
    expect(g.scores.reduce((a, b) => a + b), g.rows * g.cols);
    expect(g.owner.every((o) => o >= 0), isTrue);
    final copy = BoxesGame.replay(3, g.cols, g.moves);
    expect(copy.scores, g.scores);
  });

  test('the computer takes boxes and does not give any away', () {
    final g = BoxesGame(players: 2, size: 3);
    g.draw(g.horizontal(0, 0));
    g.draw(g.horizontal(1, 0));
    g.draw(g.vertical(0, 0));
    // Box 0 has three sides: take it.
    expect(g.boxesOf(BoxesAi().move(g)), contains(0));
    final fresh = BoxesGame(players: 2, size: 3)..draw(0);
    final l = BoxesAi(random: Random(1)).move(fresh);
    expect(fresh.boxesOf(l).every((b) => fresh.sidesDrawn(b) < 2), isTrue);
  });

  test('the strong computer wins more often than the normal one', () {
    var strong = 0, normal = 0;
    for (var seed = 0; seed < 10; seed++) {
      final g = BoxesGame(players: 2, size: 3);
      // Alternate who starts.
      final strongSeat = seed % 2;
      final ais = [
        BoxesAi(random: Random(seed), strong: strongSeat == 0),
        BoxesAi(random: Random(seed + 100), strong: strongSeat == 1),
      ];
      while (!g.isOver) {
        g.draw(ais[g.current].move(g));
      }
      final diff = g.scores[strongSeat] - g.scores[1 - strongSeat];
      if (diff > 0) strong++;
      if (diff < 0) normal++;
    }
    expect(strong, greaterThan(normal));
  });
}
