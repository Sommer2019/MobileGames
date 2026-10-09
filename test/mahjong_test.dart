import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/mahjong/mahjong_logic.dart';

void main() {
  test('layout has 120 slots and every face appears 4 times', () {
    final g = MahjongGame.generate(random: Random(1));
    expect(g.tiles.length, 120);
    final counts = <TileFace, int>{};
    for (final t in g.tiles) {
      counts[t.face] = (counts[t.face] ?? 0) + 1;
    }
    expect(counts.values, everyElement(4));
  });

  test('free rule: covered or enclosed tiles are blocked', () {
    final g = MahjongGame([
      MahjongTile(0, const Slot(0, 0, 0), allFaces[0]),
      MahjongTile(1, const Slot(2, 0, 0), allFaces[0]),
      MahjongTile(2, const Slot(4, 0, 0), allFaces[1]),
      MahjongTile(3, const Slot(4, 0, 1), allFaces[1]),
    ]);
    expect(g.isFree(g.tiles[0]), isTrue);
    expect(g.isFree(g.tiles[1]), isFalse, reason: 'neighbours left and right');
    expect(g.isFree(g.tiles[2]), isFalse, reason: 'covered');
    expect(g.isFree(g.tiles[3]), isTrue);
    expect(g.match(g.tiles[0], g.tiles[1]), isFalse);
  });

  test('portrait layout is valid too', () {
    final g = MahjongGame.generate(layout: towerLayout(), random: Random(2));
    expect(g.tiles.length, 108);
    for (final (a, b) in g.solution) {
      expect(g.match(g.tiles[a], g.tiles[b]), isTrue);
    }
    expect(g.won, isTrue);
  });

  test('the tower is a real tower and always solvable', () {
    final slots = realTowerLayout();
    expect(slots.length, 104);
    expect(slots.map((s) => s.z).reduce((a, b) => a > b ? a : b), 4);
    for (var seed = 0; seed < 5; seed++) {
      final g = MahjongGame.generate(layout: slots, random: Random(seed));
      for (final (a, b) in g.solution) {
        expect(g.match(g.tiles[a], g.tiles[b]), isTrue, reason: 'seed $seed');
      }
      expect(g.won, isTrue);
    }
    // Every shape has its own ranking.
    expect(MahjongShape.values.map((s) => s.board).toSet().length, 3);
  });

  test('generated games are always solvable', () {
    for (var seed = 0; seed < 5; seed++) {
      final g = MahjongGame.generate(random: Random(seed));
      expect(g.solution.length, 60);
      for (final (a, b) in g.solution) {
        expect(g.match(g.tiles[a], g.tiles[b]), isTrue, reason: 'seed $seed');
      }
      expect(g.won, isTrue);
    }
  });

  test('match, undo, hint and shuffle', () {
    final g = MahjongGame.generate(random: Random(3));
    final (a, b) = g.hint()!;
    expect(g.match(a, b), isTrue);
    expect(g.remaining, 118);
    expect(g.undo(), isTrue);
    expect(g.remaining, 120);
    g.shuffleRemaining(Random(4));
    expect(g.hint(), isNotNull);
  });
}
