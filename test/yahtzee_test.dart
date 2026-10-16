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

  test('every further Kniffel earns 100 bonus points', () {
    final g = KniffelGame(1);
    g.applyRoll([4, 4, 4, 4, 4]);
    g.score(KniffelCategory.kniffel);
    expect(g.sheets[0].kniffelBonus, 0);
    g.applyRoll([6, 6, 6, 6, 6]);
    g.score(KniffelCategory.sixes);
    expect(g.sheets[0].kniffelBonus, 100);
    expect(g.sheets[0].total, 50 + 30 + 100);
    g.applyRoll([2, 2, 2, 2, 2]);
    g.score(KniffelCategory.twos);
    expect(g.sheets[0].kniffelBonus, 200);
    final back = KniffelGame.fromJson(g.toJson());
    expect(back.sheets[0].kniffelBonus, 200);
    expect(back.sheets[0].total, g.sheets[0].total);
  });

  test('no Kniffel bonus after a crossed-out Fünferpasch', () {
    final g = KniffelGame(1);
    g.applyRoll([1, 2, 3, 4, 6]);
    g.score(KniffelCategory.kniffel);
    g.applyRoll([5, 5, 5, 5, 5]);
    g.score(KniffelCategory.fives);
    expect(g.sheets[0].kniffelBonus, 0);
  });

  test('joker: a further Kniffel goes into its upper box if open', () {
    final g = KniffelGame(1);
    g.applyRoll([1, 2, 3, 4, 6]);
    g.score(KniffelCategory.kniffel);
    g.applyRoll([3, 3, 3, 3, 3]);
    expect(g.canScore(KniffelCategory.fullHouse), isFalse);
    expect(g.canScore(KniffelCategory.chance), isFalse);
    expect(g.canScore(KniffelCategory.threes), isTrue);
    g.score(KniffelCategory.threes);
    // Upper box filled: any box, Full House and straights count fully.
    g.applyRoll([3, 3, 3, 3, 3]);
    final sheet = g.sheets[0];
    expect(sheet.scoreOf(KniffelCategory.fullHouse, g.dice), 25);
    expect(sheet.scoreOf(KniffelCategory.smallStraight, g.dice), 30);
    expect(sheet.scoreOf(KniffelCategory.largeStraight, g.dice), 40);
    expect(sheet.scoreOf(KniffelCategory.ones, g.dice), 0);
    expect(g.score(KniffelCategory.largeStraight), isTrue);
    expect(sheet.entries[KniffelCategory.largeStraight], 40);
    expect(sheet.kniffelBonus, 0, reason: 'Fünferpasch was crossed out');
  });

  test('games from before the extra rules play without them', () {
    final g = KniffelGame(1, extraRules: false);
    g.applyRoll([4, 4, 4, 4, 4]);
    g.score(KniffelCategory.kniffel);
    g.applyRoll([4, 4, 4, 4, 4]);
    expect(g.canScore(KniffelCategory.chance), isTrue);
    g.score(KniffelCategory.fullHouse);
    expect(g.sheets[0].entries[KniffelCategory.fullHouse], 0);
    expect(g.sheets[0].kniffelBonus, 0);
    final saved = g.toJson();
    expect(saved.containsKey('rules'), isFalse);
    expect(KniffelGame.fromJson(saved).extraRules, isFalse);
    expect(KniffelGame.fromJson(KniffelGame(1).toJson()).extraRules, isTrue);
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

  aiTests();
}

void aiTests() {
  test('AI keeps a Kniffel and scores it', () {
    final ai = KniffelAi(random: Random(1));
    final sheet = KniffelScoreSheet();
    expect(ai.chooseHolds([6, 6, 6, 6, 6], sheet, 2), everyElement(isTrue));
    expect(ai.bestCategory([6, 6, 6, 6, 6], sheet).$1, KniffelCategory.kniffel);
  });

  test('AI picks sensible categories', () {
    final ai = KniffelAi(random: Random(2));
    final sheet = KniffelScoreSheet();
    expect(
      ai.bestCategory([1, 2, 3, 4, 5], sheet).$1,
      KniffelCategory.largeStraight,
    );
    expect(
      ai.bestCategory([3, 3, 5, 5, 5], sheet).$1,
      KniffelCategory.fullHouse,
    );
    expect(
      ai.bestCategory([6, 6, 6, 6, 2], sheet).$1,
      anyOf(KniffelCategory.sixes, KniffelCategory.fourOfAKind),
    );
    // Holding: keeps the pairs/triples, not the odd die.
    final holds = ai.chooseHolds([5, 5, 5, 1, 2], sheet, 2);
    expect(holds.sublist(0, 3), everyElement(isTrue));
  });

  test('AI plays full games and scores reasonably', () {
    final rnd = Random(3);
    var total = 0;
    const games = 5;
    for (var g = 0; g < games; g++) {
      final ai = KniffelAi(random: rnd, samples: 30);
      final game = KniffelGame(1, random: rnd);
      while (!game.isOver) {
        game.roll();
        while (game.canRoll) {
          final holds = ai.chooseHolds(
            game.dice,
            game.sheets[0],
            game.rollsLeft,
          );
          if (holds.every((h) => h)) break;
          game.held = holds;
          game.roll();
        }
        expect(
          game.score(ai.bestCategory(game.dice, game.sheets[0]).$1),
          isTrue,
        );
      }
      total += game.sheets[0].total;
    }
    // Random play averages ~100, a decent strategy well above 170.
    expect(total / games, greaterThan(170));
  });
}
