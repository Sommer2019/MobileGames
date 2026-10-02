import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/solitaire/klondike_logic.dart';

const waste = PileRef(PileKind.waste);
PileRef t(int i) => PileRef(PileKind.tableau, i);
PileRef f(int i) => PileRef(PileKind.foundation, i);

KlondikeGame empty() {
  final g = KlondikeGame(random: Random(1));
  g.stock.clear();
  for (final p in g.tableau) {
    p.clear();
  }
  return g;
}

void main() {
  test('deal: 28 cards on the tableau, 24 in the stock, top cards open', () {
    final g = KlondikeGame(random: Random(3));
    for (var i = 0; i < 7; i++) {
      expect(g.tableau[i].length, i + 1);
      expect(g.tableau[i].last.faceUp, isTrue);
      expect(g.tableau[i].where((c) => c.faceUp).length, 1);
    }
    expect(g.stock.length, 24);
    final all = [...g.stock, ...g.tableau.expand((p) => p)];
    expect(all.map((c) => c.suit * 13 + c.rank).toSet().length, 52);
  });

  test('stacking rules: alternate colours down, kings on empty piles', () {
    final g = empty();
    g.tableau[0].add(PlayingCard(0, 8, faceUp: true)); // 8♠
    g.waste.add(PlayingCard(1, 7, faceUp: true)); // 7♥
    expect(g.canMove(waste, 0, t(0)), isTrue);
    g.waste
      ..clear()
      ..add(PlayingCard(3, 7, faceUp: true)); // 7♣ same colour
    expect(g.canMove(waste, 0, t(0)), isFalse);
    g.waste
      ..clear()
      ..add(PlayingCard(2, 13, faceUp: true)); // K♦
    expect(g.canMove(waste, 0, t(1)), isTrue);
    expect(g.canMove(waste, 0, t(0)), isFalse);
  });

  test('foundation needs ace first, then same suit upwards', () {
    final g = empty();
    g.waste.add(PlayingCard(1, 2, faceUp: true));
    expect(g.bestTarget(waste, 0), isNull);
    g.waste.insert(0, PlayingCard(1, 1, faceUp: true));
    g.waste.removeLast();
    expect(g.bestTarget(waste, 0), f(0));
    expect(g.move(waste, 0, f(0)), isTrue);
    g.waste.add(PlayingCard(1, 2, faceUp: true));
    expect(g.move(waste, 0, f(0)), isTrue);
    expect(g.foundations[0].length, 2);
  });

  test('moving a run flips the new top card; undo restores', () {
    final g = empty();
    g.tableau[0].addAll([
      PlayingCard(0, 3),
      PlayingCard(1, 9, faceUp: true),
      PlayingCard(0, 8, faceUp: true),
    ]);
    g.tableau[1].add(PlayingCard(3, 10, faceUp: true));
    expect(g.move(t(0), 1, t(1)), isTrue);
    expect(g.tableau[1].length, 3);
    expect(g.tableau[0].single.faceUp, isTrue);
    expect(g.undo(), isTrue);
    expect(g.tableau[0].length, 3);
    expect(g.tableau[0].first.faceUp, isFalse);
    expect(g.tableau[1].length, 1);
  });

  test('draw 1 / draw 3 and recycling the waste', () {
    final g = KlondikeGame(drawCount: 3, random: Random(2));
    g.draw();
    expect(g.waste.length, 3);
    expect(g.stock.length, 21);
    while (g.stock.isNotEmpty) {
      g.draw();
    }
    expect(g.waste.length, 24);
    g.draw(); // turn over
    expect(g.stock.length, 24);
    expect(g.waste, isEmpty);
    expect(g.stock.every((c) => !c.faceUp), isTrue);
  });

  test('auto complete finishes an open game', () {
    final g = empty();
    // Four piles each holding one suit from K down to A, all face up.
    for (var s = 0; s < 4; s++) {
      for (var r = 13; r >= 1; r--) {
        g.tableau[s].add(PlayingCard(s, r, faceUp: true));
      }
    }
    expect(g.canAutoComplete, isTrue);
    var steps = 0;
    while (g.autoStep()) {
      steps++;
    }
    expect(steps, 52);
    expect(g.won, isTrue);
  });

  test('greedy play never makes illegal moves', () {
    for (var seed = 0; seed < 20; seed++) {
      final g = KlondikeGame(random: Random(seed));
      for (var turn = 0; turn < 400 && !g.won; turn++) {
        var moved = false;
        for (var i = 0; i < 7 && !moved; i++) {
          final p = g.tableau[i];
          for (var idx = 0; idx < p.length && !moved; idx++) {
            final to = g.bestTarget(t(i), idx);
            if (to != null &&
                !(to.kind == PileKind.tableau &&
                    idx == 0 &&
                    g.tableau[to.index].isEmpty)) {
              moved = g.move(t(i), idx, to);
            }
          }
        }
        if (!moved && g.waste.isNotEmpty) {
          final to = g.bestTarget(waste, g.waste.length - 1);
          if (to != null) moved = g.move(waste, g.waste.length - 1, to);
        }
        if (!moved) g.draw();
        final cards =
            g.stock.length +
            g.waste.length +
            g.foundations.fold(0, (a, p) => a + p.length) +
            g.tableau.fold(0, (a, p) => a + p.length);
        expect(cards, 52);
      }
    }
  });

  test('scoring: waste/foundation/turn/recycle, undo restores, never < 0', () {
    final g = empty();
    g.tableau[0].addAll([
      PlayingCard(2, 5), // hidden
      PlayingCard(0, 8, faceUp: true),
    ]);
    g.waste.add(PlayingCard(1, 7, faceUp: true));
    expect(g.move(waste, 0, t(0)), isTrue);
    expect(g.score, 5);
    g.waste.add(PlayingCard(3, 1, faceUp: true));
    expect(g.move(waste, 0, f(0)), isTrue);
    expect(g.score, 15);
    // Moving 8♠ 7♥ to an empty pile is not allowed (no king), so move
    // the ace back down and check the penalty.
    g.tableau[1].add(PlayingCard(1, 2, faceUp: true));
    expect(g.move(f(0), 0, t(1)), isTrue);
    expect(g.score, 0);
    expect(g.undo(), isTrue);
    expect(g.score, 15);
    // Turning over a hidden card.
    g.tableau[2].add(PlayingCard(1, 13, faceUp: true));
    g.tableau[0].removeRange(1, 3);
    g.tableau[0].add(PlayingCard(3, 12, faceUp: true));
    expect(g.move(t(0), 1, t(2)), isTrue);
    expect(g.tableau[0].last.faceUp, isTrue);
    expect(g.score, 20);
    // Recycling the waste costs points, but never below zero.
    g.waste.add(PlayingCard(0, 4, faceUp: true));
    expect(g.draw(), isTrue);
    expect(g.score, 0);
    expect(KlondikeGame.timeBonus(10), 23333);
    expect(KlondikeGame.timeBonus(700), 1000);
  });
}
