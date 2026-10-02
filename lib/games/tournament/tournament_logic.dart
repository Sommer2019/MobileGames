/// Points table for a tournament: [rounds] rounds over a list of games.
///
/// A win gives 3 points, a draw 1 point for everybody involved.
class Tournament {
  Tournament({
    required List<String> games,
    required this.rounds,
    required this.players,
  }) : schedule = [for (var r = 0; r < rounds; r++) ...games],
       points = List.filled(players, 0),
       wins = List.filled(players, 0);

  final int rounds;
  final int players;

  /// Game id of every match in order.
  final List<String> schedule;
  final List<int> points;
  final List<int> wins;
  final Map<int, List<int>> results = {};

  int get matchCount => schedule.length;
  bool get finished => results.length >= matchCount;

  /// Index of the next match that still has to be played.
  int get nextMatch {
    for (var i = 0; i < matchCount; i++) {
      if (!results.containsKey(i)) return i;
    }
    return matchCount;
  }

  /// Records the winners of match [index] (all seats = draw). Duplicate
  /// reports for the same match are ignored.
  void record(int index, List<int> winnerSeats) {
    if (index < 0 || index >= matchCount || results.containsKey(index)) return;
    final winners = winnerSeats.toSet().where((s) => s >= 0 && s < players);
    results[index] = winners.toList();
    final draw = winners.length >= players || winners.isEmpty;
    for (final s in winners) {
      points[s] += draw ? 1 : 3;
      if (!draw) wins[s]++;
    }
  }

  /// Seats ordered by points, then wins.
  List<int> ranking() {
    final seats = [for (var i = 0; i < players; i++) i];
    seats.sort((a, b) {
      final p = points[b].compareTo(points[a]);
      return p != 0 ? p : wins[b].compareTo(wins[a]);
    });
    return seats;
  }

  /// Seats sharing the first place.
  List<int> leaders() {
    final best = ranking().first;
    return [
      for (var i = 0; i < players; i++)
        if (points[i] == points[best] && wins[i] == wins[best]) i,
    ];
  }
}
