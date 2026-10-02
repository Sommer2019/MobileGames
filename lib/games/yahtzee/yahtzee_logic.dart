import 'dart:math';

enum KniffelCategory {
  ones('Einser'),
  twos('Zweier'),
  threes('Dreier'),
  fours('Vierer'),
  fives('Fünfer'),
  sixes('Sechser'),
  threeOfAKind('Dreierpasch'),
  fourOfAKind('Viererpasch'),
  fullHouse('Full House'),
  smallStraight('Kleine Straße'),
  largeStraight('Große Straße'),
  kniffel('Kniffel'),
  chance('Chance');

  const KniffelCategory(this.label);
  final String label;

  bool get isUpper => index <= KniffelCategory.sixes.index;
}

/// Scores five dice for a category according to the classic Kniffel rules.
int scoreFor(KniffelCategory cat, List<int> dice) {
  assert(dice.length == 5);
  final counts = List.filled(7, 0);
  for (final d in dice) {
    counts[d]++;
  }
  final sum = dice.fold(0, (a, b) => a + b);
  bool hasRun(int len) {
    var run = 0;
    for (var v = 1; v <= 6; v++) {
      run = counts[v] > 0 ? run + 1 : 0;
      if (run >= len) return true;
    }
    return false;
  }

  switch (cat) {
    case KniffelCategory.ones:
    case KniffelCategory.twos:
    case KniffelCategory.threes:
    case KniffelCategory.fours:
    case KniffelCategory.fives:
    case KniffelCategory.sixes:
      final face = cat.index + 1;
      return counts[face] * face;
    case KniffelCategory.threeOfAKind:
      return counts.any((c) => c >= 3) ? sum : 0;
    case KniffelCategory.fourOfAKind:
      return counts.any((c) => c >= 4) ? sum : 0;
    case KniffelCategory.fullHouse:
      return (counts.contains(3) && counts.contains(2)) ? 25 : 0;
    case KniffelCategory.smallStraight:
      return hasRun(4) ? 30 : 0;
    case KniffelCategory.largeStraight:
      return hasRun(5) ? 40 : 0;
    case KniffelCategory.kniffel:
      return counts.contains(5) ? 50 : 0;
    case KniffelCategory.chance:
      return sum;
  }
}

class KniffelScoreSheet {
  final Map<KniffelCategory, int> entries = {};

  bool isFilled(KniffelCategory c) => entries.containsKey(c);
  bool get complete => entries.length == KniffelCategory.values.length;

  int get upperSum => entries.entries
      .where((e) => e.key.isUpper)
      .fold(0, (a, e) => a + e.value);
  int get bonus => upperSum >= 63 ? 35 : 0;
  int get lowerSum => entries.entries
      .where((e) => !e.key.isUpper)
      .fold(0, (a, e) => a + e.value);
  int get total => upperSum + bonus + lowerSum;

  Map<String, int> toJson() => {
    for (final e in entries.entries) e.key.name: e.value,
  };
}

/// State of a Kniffel game for any number of players.
class KniffelGame {
  KniffelGame(this.playerCount, {Random? random})
    : sheets = List.generate(playerCount, (_) => KniffelScoreSheet()),
      _random = random ?? Random();

  final int playerCount;
  final List<KniffelScoreSheet> sheets;
  final Random _random;

  List<int> dice = [1, 1, 1, 1, 1];
  List<bool> held = List.filled(5, false);
  int rollsLeft = 3;
  int currentPlayer = 0;

  bool get hasRolled => rollsLeft < 3;
  bool get canRoll => rollsLeft > 0 && !isOver;
  bool get isOver => sheets.every((s) => s.complete);

  /// Rolls all non-held dice. Returns the new dice values.
  List<int> roll() {
    if (!canRoll) return dice;
    final next = List<int>.from(dice);
    for (var i = 0; i < 5; i++) {
      if (!held[i] || !hasRolled) next[i] = _random.nextInt(6) + 1;
    }
    applyRoll(next);
    return dice;
  }

  /// Applies a roll result (used for rolls received from a remote peer).
  void applyRoll(List<int> values) {
    if (!hasRolled) held = List.filled(5, false);
    dice = List<int>.from(values);
    rollsLeft--;
  }

  void toggleHold(int i) {
    if (!hasRolled || rollsLeft == 0) return;
    held[i] = !held[i];
  }

  bool canScore(KniffelCategory c) =>
      hasRolled && !sheets[currentPlayer].isFilled(c);

  /// Writes the current dice into the given category and passes the turn.
  bool score(KniffelCategory c) {
    if (!canScore(c)) return false;
    sheets[currentPlayer].entries[c] = scoreFor(c, dice);
    currentPlayer = (currentPlayer + 1) % playerCount;
    rollsLeft = 3;
    held = List.filled(5, false);
    return true;
  }

  /// Indices of the players with the highest total (several on a tie).
  List<int> winners() {
    final best = sheets.map((s) => s.total).reduce(max);
    return [
      for (var i = 0; i < playerCount; i++)
        if (sheets[i].total == best) i,
    ];
  }
}
