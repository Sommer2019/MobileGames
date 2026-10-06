import 'dart:math';

/// 75-ball bingo. Cards and the draw order follow from one seed, so every
/// device in a room knows all of them after the host sent the seed.
class BingoGame {
  BingoGame({required this.players, required this.seed})
    : order = (List.generate(75, (i) => i + 1)..shuffle(Random(seed))),
      cards = [for (var p = 0; p < players; p++) cardFor(seed, p)];

  final int players;
  final int seed;

  /// The balls in the order they are drawn.
  final List<int> order;

  /// 25 numbers per card, row by row; 0 is the free centre.
  final List<List<int>> cards;

  int drawn = 0;
  int? winner;

  bool get isOver => winner != null;
  bool get allDrawn => drawn >= order.length;
  int? get lastBall => drawn == 0 ? null : order[drawn - 1];
  Set<int> get drawnSet => order.take(drawn).toSet();

  static const letters = 'BINGO';
  static String letterOf(int ball) => letters[(ball - 1) ~/ 15];

  static List<int> cardFor(int seed, int player) {
    final r = Random(seed * 31 + player * 7919 + 1);
    final columns = [
      for (var c = 0; c < 5; c++)
        (List.generate(15, (i) => c * 15 + i + 1)..shuffle(r)).take(5).toList(),
    ];
    return [
      for (var row = 0; row < 5; row++)
        for (var c = 0; c < 5; c++) row == 2 && c == 2 ? 0 : columns[c][row],
    ];
  }

  /// The 12 lines (rows, columns, diagonals) as cell indices.
  static final List<List<int>> lines = [
    for (var r = 0; r < 5; r++) [for (var c = 0; c < 5; c++) r * 5 + c],
    for (var c = 0; c < 5; c++) [for (var r = 0; r < 5; r++) r * 5 + c],
    [for (var i = 0; i < 5; i++) i * 6],
    [for (var i = 0; i < 5; i++) i * 4 + 4],
  ];

  bool draw() {
    if (isOver || allDrawn) return false;
    drawn++;
    return true;
  }

  /// Cells of [player]'s card that count as covered for [covered] numbers.
  static bool _complete(List<int> card, List<int> line, Set<int> covered) =>
      line.every((i) => card[i] == 0 || covered.contains(card[i]));

  /// Whether the drawn balls complete a line on [player]'s card.
  bool hasBingo(int player) {
    final d = drawnSet;
    return lines.any((l) => _complete(cards[player], l, d));
  }

  /// Whether the [marked] numbers (only drawn ones count) complete a line.
  bool markedBingo(int player, Set<int> marked) {
    final m = marked.intersection(drawnSet);
    return lines.any((l) => _complete(cards[player], l, m));
  }

  /// Fewest numbers still missing for a line.
  int missing(int player) {
    final d = drawnSet;
    var best = 5;
    for (final l in lines) {
      final miss = l
          .where((i) => cards[player][i] != 0 && !d.contains(cards[player][i]))
          .length;
      best = min(best, miss);
    }
    return best;
  }

  /// Accepts a claim if it is valid and nobody won yet.
  bool claim(int player) {
    if (isOver || !hasBingo(player)) return false;
    winner = player;
    return true;
  }
}
