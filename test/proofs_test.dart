import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/leaderboard.dart';
import 'package:mobile_games/core/proof.dart';
import 'package:mobile_games/games/mahjong/mahjong_logic.dart';
import 'package:mobile_games/games/snake/snake_logic.dart';
import 'package:mobile_games/games/solitaire/klondike_logic.dart';

/// Round trip through JSON, as on the relays.
Map<String, dynamic> wire(Map<String, dynamic> proof) =>
    jsonDecode(jsonEncode(proof)) as Map<String, dynamic>;

/// A simple snake bot: heads for the food, avoids walls and itself.
SnakeGame playSnake(String owner) {
  final g = SnakeGame(seed: newProofSeed(owner));
  while (!g.dead && g.steps < 3000) {
    final (hx, hy) = g.body.first;
    final (fx, fy) = g.food;
    bool safe(Dir d) {
      final (dx, dy) = d.delta;
      final n = (hx + dx, hy + dy);
      return n.$1 >= 0 &&
          n.$2 >= 0 &&
          n.$1 < g.width &&
          n.$2 < g.height &&
          !g.body.sublist(0, g.body.length - 1).contains(n);
    }

    final wanted = [
      if (fx < hx) Dir.left,
      if (fx > hx) Dir.right,
      if (fy < hy) Dir.up,
      if (fy > hy) Dir.down,
      ...Dir.values,
    ];
    final d = wanted.firstWhere(
      (d) => safe(d) && !d.isOpposite(g.direction),
      orElse: () => g.direction,
    );
    g.turn(d);
    g.step();
  }
  return g;
}

/// Greedy Klondike player; true if it won.
bool playKlondike(KlondikeGame g) {
  var idle = 0;
  while (!g.won && idle < 60 && g.log!.length < 3000) {
    var moved = false;
    if (g.autoStep()) continue;
    for (var t = 0; t < 7 && !moved; t++) {
      final pile = g.tableau[t];
      final first = pile.indexWhere((c) => c.faceUp);
      if (first < 0) continue;
      final to = g.bestTarget(PileRef(PileKind.tableau, t), first);
      // Only moves that uncover a card (or free a column for a king).
      if (to != null && first > 0) {
        moved = g.move(PileRef(PileKind.tableau, t), first, to);
      }
    }
    if (!moved && g.waste.isNotEmpty) {
      const w = PileRef(PileKind.waste);
      final to = g.bestTarget(w, g.waste.length - 1);
      if (to != null) moved = g.move(w, g.waste.length - 1, to);
    }
    if (moved) {
      idle = 0;
      continue;
    }
    if (!g.draw()) break;
    idle++;
  }
  return g.won;
}

void main() {
  test('snake: the played score is proven, changes are caught', () {
    final g = playSnake('anna');
    expect(g.dead, isTrue);
    expect(g.score, greaterThan(3));
    final proof = wire(SnakeProof.of(g));
    expect(SnakeProof.verify(proof, 'anna'), g.score);
    expect(Leaderboard.verify('snake', proof, 'anna'), g.score);
    expect(SnakeProof.verify(proof, 'ben'), isNull);
    // One turn earlier changes the game.
    final moves = List<String>.from(proof['m'] as List);
    final i = moves.length ~/ 2;
    final m = moves[i];
    moves[i] =
        '${int.parse(m.substring(0, m.length - 1)) - 1}${m[m.length - 1]}';
    expect(SnakeProof.verify({...proof, 'm': moves}, 'anna'), isNot(g.score));
    // A game that is not over does not count.
    expect(SnakeProof.verify({...proof, 'n': g.steps - 1}, 'anna'), isNull);
  });

  test('klondike: a won game is proven, too fast is refused', () {
    KlondikeGame? won;
    for (var i = 0; i < 300 && won == null; i++) {
      final g = KlondikeGame(seed: 'anna:$i');
      if (playKlondike(g)) won = g;
    }
    expect(won, isNotNull, reason: 'the greedy player wins sometimes');
    final g = won!;
    final actions = g.log!.length;
    final seconds = (actions * 0.5).ceil();
    final proof = wire(KlondikeProof.of(g, seconds));
    final expected = g.score + KlondikeGame.timeBonus(seconds);
    expect(KlondikeProof.verify(proof, 'anna'), expected);
    expect(Leaderboard.verify('klondike', proof, 'anna'), expected);
    expect(KlondikeProof.verify(proof, 'ben'), isNull);
    // Faster than possible.
    expect(KlondikeProof.verify({...proof, 't': 5}, 'anna'), isNull);
    // Not won (last action missing).
    final moves = List<String>.from(proof['m'] as List)..removeLast();
    expect(KlondikeProof.verify({...proof, 'm': moves}, 'anna'), isNull);
  });

  test('mahjong: a solved board is proven, on its own ranking only', () {
    for (final shape in MahjongShape.values) {
      final g = MahjongGame.generate(
        layout: shape.layout(),
        seed: 'anna:${shape.name}',
      );
      // A wrong pair, taken back.
      final (a0, b0) = g.solution.first;
      g.match(g.tiles[a0], g.tiles[b0]);
      g.undo();
      for (final (a, b) in g.solution) {
        expect(g.match(g.tiles[a], g.tiles[b]), isTrue);
      }
      expect(g.won, isTrue);
      final pairs = g.tiles.length ~/ 2 + 1;
      final proof = wire(MahjongProof.of(g, shape, pairs + 10));
      expect(MahjongProof.verify(shape.board, proof, 'anna'), pairs + 10);
      expect(Leaderboard.verify(shape.board, proof, 'anna'), pairs + 10);
      // Too fast, someone else, or another ranking.
      expect(
        MahjongProof.verify(shape.board, {...proof, 't': 20}, 'anna'),
        isNull,
      );
      expect(MahjongProof.verify(shape.board, proof, 'ben'), isNull);
      final other = MahjongShape.values.firstWhere((s) => s != shape);
      expect(MahjongProof.verify(other.board, proof, 'anna'), isNull);
    }
  });

  test('seeded randomness is the same on every run', () {
    final a = SeededRandom('x'), b = SeededRandom('x');
    final big = [for (var i = 0; i < 200; i++) a.nextInt(144)];
    expect([for (var i = 0; i < 200; i++) b.nextInt(144)], big);
    expect(big.toSet().length, greaterThan(100));
    final g1 = KlondikeGame(seed: 's'), g2 = KlondikeGame(seed: 's');
    expect(g1.toJson(), g2.toJson());
  });
}
