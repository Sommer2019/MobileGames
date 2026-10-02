import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_logic.dart';

void main() {
  test('category scoring', () {
    expect(scoreFor(KniffelCategory.threes, [3, 3, 1, 3, 6]), 9);
    expect(scoreFor(KniffelCategory.threeOfAKind, [3, 3, 1, 3, 6]), 16);
    expect(scoreFor(KniffelCategory.fourOfAKind, [3, 3, 1, 3, 6]), 0);
    expect(scoreFor(KniffelCategory.fourOfAKind, [5, 5, 5, 5, 2]), 22);
    expect(scoreFor(KniffelCategory.fullHouse, [2, 2, 5, 5, 5]), 25);
    expect(scoreFor(KniffelCategory.fullHouse, [5, 5, 5, 5, 5]), 0);
    expect(scoreFor(KniffelCategory.smallStraight, [1, 2, 3, 4, 6]), 30);
    expect(scoreFor(KniffelCategory.smallStraight, [3, 4, 5, 6, 6]), 30);
    expect(scoreFor(KniffelCategory.smallStraight, [1, 2, 3, 5, 6]), 0);
    expect(scoreFor(KniffelCategory.largeStraight, [2, 3, 4, 5, 6]), 40);
    expect(scoreFor(KniffelCategory.largeStraight, [1, 2, 3, 4, 6]), 0);
    expect(scoreFor(KniffelCategory.kniffel, [4, 4, 4, 4, 4]), 50);
    expect(scoreFor(KniffelCategory.chance, [1, 2, 3, 4, 6]), 16);
  });

  test('upper bonus at 63 points', () {
    final s = KniffelScoreSheet();
    s.entries[KniffelCategory.ones] = 3;
    s.entries[KniffelCategory.twos] = 6;
    s.entries[KniffelCategory.threes] = 9;
    s.entries[KniffelCategory.fours] = 12;
    s.entries[KniffelCategory.fives] = 15;
    s.entries[KniffelCategory.sixes] = 18;
    expect(s.upperSum, 63);
    expect(s.bonus, 35);
    expect(s.total, 98);
  });

  test('turn flow: max three rolls, held dice stay, turns rotate', () {
    final g = KniffelGame(2, random: Random(1));
    expect(
      g.canScore(KniffelCategory.chance),
      isFalse,
      reason: 'must roll first',
    );
    g.roll();
    final first = List<int>.from(g.dice);
    g.toggleHold(0);
    g.toggleHold(1);
    g.roll();
    expect(g.dice[0], first[0]);
    expect(g.dice[1], first[1]);
    g.roll();
    expect(g.canRoll, isFalse);
    expect(g.score(KniffelCategory.chance), isTrue);
    expect(g.currentPlayer, 1);
    expect(g.rollsLeft, 3);
    expect(g.held, everyElement(isFalse));
  });

  test('full game ends after 13 rounds per player', () {
    final g = KniffelGame(2, random: Random(7));
    for (var round = 0; round < 13; round++) {
      for (var p = 0; p < 2; p++) {
        g.roll();
        final cat = KniffelCategory.values.firstWhere((c) => g.canScore(c));
        g.score(cat);
      }
    }
    expect(g.isOver, isTrue);
    expect(g.canRoll, isFalse);
    expect(g.winners(), isNotEmpty);
  });
}
