import 'dart:math';

/// A domino tile of the double-six set (0 … 27).
class Domino {
  Domino._();

  static final List<(int, int)> tiles = [
    for (var a = 0; a <= 6; a++)
      for (var b = a; b <= 6; b++) (a, b),
  ];

  static int pips(int tile) => tiles[tile].$1 + tiles[tile].$2;
  static bool isDouble(int tile) => tiles[tile].$1 == tiles[tile].$2;
}

/// A tile on the table, oriented: [a] faces left, [b] faces right.
class PlacedTile {
  const PlacedTile(this.tile, this.a, this.b);
  final int tile;
  final int a;
  final int b;
}

/// A domino match (draw game): rounds until someone has [target] points.
///
/// Everything happens through [apply] with plain events, so a match can be
/// sent over the network and saved as a list of events:
/// `['deal', seed]`, `['play', tile, side]` (side 0 = left, 1 = right),
/// `['draw']`, `['pass']`.
class DominoMatch {
  DominoMatch({required this.players, this.first = 0, this.target = 100})
    : scores = List.filled(players, 0);

  factory DominoMatch.replay(
    int players,
    List events, {
    int first = 0,
    int target = 100,
  }) {
    final m = DominoMatch(players: players, first: first, target: target);
    for (final e in events) {
      m.apply(List.from(e as List));
    }
    return m;
  }

  final int players;
  final int first;
  final int target;
  final List<int> scores;
  final List<List> events = [];

  int round = -1;

  /// Number of the match (counts rematches), decides who starts.
  int match = 0;
  List<List<int>> hands = [];
  List<int> boneyard = [];
  List<PlacedTile> line = [];
  int current = 0;
  int _passes = 0;

  /// Result of the finished round: winner (null = tie when blocked) and the
  /// points scored.
  bool roundOver = true;
  int? roundWinner;
  int roundPoints = 0;
  bool blocked = false;

  int get handSize => players == 2 ? 7 : 5;
  bool get dealt => round >= 0;
  int? get left => line.isEmpty ? null : line.first.a;
  int? get right => line.isEmpty ? null : line.last.b;

  int? get winner {
    for (var p = 0; p < players; p++) {
      if (scores[p] >= target) return p;
    }
    return null;
  }

  bool get isOver => roundOver && winner != null;

  /// The seat that has to act now, or null while waiting for a deal.
  int? get toMove => roundOver ? null : current;

  /// Sides (0 left, 1 right) where [tile] fits.
  List<int> sidesFor(int tile) {
    if (line.isEmpty) return const [1];
    final (a, b) = Domino.tiles[tile];
    return [if (a == left || b == left) 0, if (a == right || b == right) 1];
  }

  List<int> playable([int? player]) => [
    for (final t in hands[player ?? current])
      if (sidesFor(t).isNotEmpty) t,
  ];

  bool get canDraw => playable().isEmpty && boneyard.isNotEmpty;
  bool get mustPass => playable().isEmpty && boneyard.isEmpty;

  int handPips(int player) =>
      hands[player].fold(0, (s, t) => s + Domino.pips(t));

  /// Applies one event; returns false (and changes nothing) if it is not
  /// allowed.
  bool apply(List e) {
    switch (e) {
      case ['deal', final int seed]:
        if (!roundOver) return false;
        if (isOver) {
          // New match.
          scores.fillRange(0, players, 0);
          round = -1;
          match++;
        }
        _deal(seed);
      case ['play', final int tile, final int side]:
        if (roundOver || !hands[current].contains(tile)) return false;
        if (!sidesFor(tile).contains(side)) return false;
        _place(tile, side);
        hands[current].remove(tile);
        _passes = 0;
        if (hands[current].isEmpty) {
          _endRound(current);
        } else {
          _next();
        }
      case ['draw']:
        if (roundOver || !canDraw) return false;
        hands[current].add(boneyard.removeLast());
      case ['pass']:
        if (roundOver || !mustPass) return false;
        _passes++;
        if (_passes >= players) {
          _endBlocked();
        } else {
          _next();
        }
      default:
        return false;
    }
    events.add(e);
    return true;
  }

  void _deal(int seed) {
    round++;
    final pool = List.generate(Domino.tiles.length, (i) => i)
      ..shuffle(Random(seed));
    hands = [
      for (var p = 0; p < players; p++)
        pool.sublist(p * handSize, (p + 1) * handSize),
    ];
    boneyard = pool.sublist(players * handSize);
    line = [];
    current = (first + match + round) % players;
    _passes = 0;
    roundOver = false;
    roundWinner = null;
    roundPoints = 0;
    blocked = false;
  }

  void _place(int tile, int side) {
    final (a, b) = Domino.tiles[tile];
    if (line.isEmpty) {
      line.add(PlacedTile(tile, a, b));
    } else if (side == 0) {
      line.insert(
        0,
        b == left ? PlacedTile(tile, a, b) : PlacedTile(tile, b, a),
      );
    } else {
      line.add(a == right ? PlacedTile(tile, a, b) : PlacedTile(tile, b, a));
    }
  }

  void _next() => current = (current + 1) % players;

  void _endRound(int w) {
    var pts = 0;
    for (var p = 0; p < players; p++) {
      if (p != w) pts += handPips(p);
    }
    roundOver = true;
    roundWinner = w;
    roundPoints = pts;
    scores[w] += pts;
  }

  void _endBlocked() {
    blocked = true;
    final pips = [for (var p = 0; p < players; p++) handPips(p)];
    final low = pips.reduce(min);
    final lows = [
      for (var p = 0; p < players; p++)
        if (pips[p] == low) p,
    ];
    if (lows.length > 1) {
      roundOver = true;
      roundWinner = null;
      roundPoints = 0;
      return;
    }
    final w = lows.single;
    var pts = 0;
    for (var p = 0; p < players; p++) {
      if (p != w) pts += pips[p] - low;
    }
    roundOver = true;
    roundWinner = w;
    roundPoints = pts;
    scores[w] += pts;
  }
}

/// Computer player: plays the heaviest tile (doubles first, they are hard
/// to get rid of), keeps the numbers it holds most of open.
class DominoAi {
  static List choose(DominoMatch m) {
    final options = m.playable();
    if (options.isEmpty) return m.canDraw ? ['draw'] : ['pass'];
    final hand = m.hands[m.current];
    int count(int n) => hand.where((t) {
      final (a, b) = Domino.tiles[t];
      return a == n || b == n;
    }).length;
    List? best;
    var bestScore = -1 << 30;
    for (final t in options) {
      for (final side in m.sidesFor(t)) {
        final (a, b) = Domino.tiles[t];
        final end = side == 0 ? m.left : m.right;
        final open = end == null ? b : (a == end ? b : a);
        final score =
            Domino.pips(t) * 2 +
            (Domino.isDouble(t) ? 8 : 0) +
            (count(open) - 1) * 3;
        if (score > bestScore) {
          bestScore = score;
          best = ['play', t, side];
        }
      }
    }
    return best!;
  }
}
