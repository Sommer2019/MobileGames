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

  test('endgame values: keeping control beats taking everything', () {
    expect(endgameValue([(3, false)]), -3);
    // Opener gives a 3-chain, the other keeps control: 4 : 2.
    expect(endgameValue([(3, false), (3, false)]), -2);
    expect(endgameValue([(4, false), (4, false), (4, false)]), -4);
    // Short chains first: opening a single box costs least.
    expect(endgameValue([(1, false), (5, false)]), 4);
  });

  test('the computer leaves the last two boxes to keep control', () {
    // 4 × 4 board, all horizontal lines drawn: four chains of four boxes,
    // one per row, closed off by the vertical lines.
    final g = BoxesGame(players: 2, size: 4);
    for (var r = 0; r <= 4; r++) {
      for (var c = 0; c < 4; c++) {
        g.draw(g.horizontal(r, c));
      }
    }
    // Player 0 has to open a chain: the left end of row 0.
    final opener = g.current;
    g.draw(g.vertical(0, 0));
    final ai = BoxesAi(random: Random(1));
    // The computer takes the first two boxes …
    expect(g.current, isNot(opener));
    g.draw(ai.move(g));
    g.draw(ai.move(g));
    expect(g.scores[1 - opener], 2);
    // … and then hands the last two over instead of taking them.
    final line = ai.move(g);
    expect(line, g.vertical(0, 4));
    g.draw(line);
    expect(g.current, opener);
    // The opener takes the pair and has to open the next chain again.
    final chains = boxChains(g)!;
    expect(chains.cold.length, 3);
  });

  test('the computer keeps control and beats a greedy player', () {
    var wins = 0, losses = 0;
    for (var seed = 0; seed < 30; seed++) {
      final g = BoxesGame(players: 2, size: 4, first: seed % 2);
      final smart = BoxesAi(random: Random(seed));
      final rnd = Random(seed + 100);
      while (!g.isOver) {
        if (g.current == 0) {
          g.draw(smart.move(g));
        } else {
          // Greedy: takes every box, else a safe line, else the cheapest.
          g.draw(_greedy(g, rnd));
        }
      }
      if (g.scores[0] > g.scores[1]) wins++;
      if (g.scores[0] < g.scores[1]) losses++;
    }
    expect(wins, greaterThan(losses * 2));
  });
}

/// The old computer: always takes everything.
int _greedy(BoxesGame g, Random r) {
  final open = g.openLines;
  for (final l in open) {
    if (g.boxesOf(l).any((b) => g.sidesDrawn(b) == 3)) return l;
  }
  final safe = [
    for (final l in open)
      if (g.boxesOf(l).every((b) => g.sidesDrawn(b) < 2)) l,
  ];
  if (safe.isNotEmpty) return safe[r.nextInt(safe.length)];
  return open[r.nextInt(open.length)];
}
