import 'dart:math';

/// Chinese checkers (Sternhalma) on the 121-hole star.
///
/// Cells use cube coordinates (x, y, z with x + y + z = 0). The star is the
/// union of the triangles {x, y, z ≥ −4} and {x, y, z ≤ 4}; the inner
/// hexagon has all coordinates within ±4, each of the six arms (10 holes)
/// has one coordinate beyond.
class HalmaBoard {
  HalmaBoard._();

  static final List<(int, int, int)> cells = [
    for (var x = -8; x <= 8; x++)
      for (var y = -8; y <= 8; y++)
        if (_inStar(x, y, -x - y)) (x, y, -x - y),
  ];

  static final Map<(int, int, int), int> index = {
    for (var i = 0; i < cells.length; i++) cells[i]: i,
  };

  static bool _inStar(int x, int y, int z) =>
      (x >= -4 && y >= -4 && z >= -4) || (x <= 4 && y <= 4 && z <= 4);

  /// The six directions to the neighbours.
  static const dirs = [
    (1, -1, 0),
    (1, 0, -1),
    (0, 1, -1),
    (-1, 1, 0),
    (-1, 0, 1),
    (0, -1, 1),
  ];

  /// Arm of a cell (0–5 in turning order, k + 3 is opposite), or −1 for the
  /// middle.
  static int armOf(int cell) {
    final (x, y, z) = cells[cell];
    if (x > 4) return 0;
    if (z < -4) return 1;
    if (y > 4) return 2;
    if (x < -4) return 3;
    if (z > 4) return 4;
    if (y < -4) return 5;
    return -1;
  }

  static final List<List<int>> arms = [
    for (var a = 0; a < 6; a++)
      [
        for (var i = 0; i < cells.length; i++)
          if (armOf(i) == a) i,
      ],
  ];

  /// The tip of each arm (its outermost hole).
  static final List<int> tips = [
    for (var a = 0; a < 6; a++)
      arms[a].reduce((p, q) => _norm(p) >= _norm(q) ? p : q),
  ];

  static int _norm(int c) {
    final (x, y, z) = cells[c];
    return max(x.abs(), max(y.abs(), z.abs()));
  }

  static int? neighbour(int cell, (int, int, int) d, [int times = 1]) {
    final (x, y, z) = cells[cell];
    return index[(x + d.$1 * times, y + d.$2 * times, z + d.$3 * times)];
  }

  static int distance(int a, int b) {
    final (x1, y1, z1) = cells[a];
    final (x2, y2, z2) = cells[b];
    return max((x1 - x2).abs(), max((y1 - y2).abs(), (z1 - z2).abs()));
  }

  /// Arms the players start in.
  static List<int> homeArms(int players) => switch (players) {
    2 => const [0, 3],
    3 => const [0, 2, 4],
    4 => const [1, 2, 4, 5],
    _ => const [0, 1, 2, 3, 4, 5],
  };
}

class HalmaGame {
  HalmaGame({required this.players, int first = 0})
    : current = first % players,
      homes = HalmaBoard.homeArms(players) {
    owner = List.filled(HalmaBoard.cells.length, -1);
    for (var p = 0; p < players; p++) {
      for (final c in HalmaBoard.arms[homes[p]]) {
        owner[c] = p;
      }
    }
  }

  factory HalmaGame.replay(int players, List moves, {int first = 0}) {
    final g = HalmaGame(players: players, first: first);
    for (final m in moves) {
      g.move(List<int>.from(m as List));
    }
    return g;
  }

  final int players;
  final List<int> homes;
  late final List<int> owner;
  int current;
  int? winner;
  final List<List<int>> moves = [];

  bool get isOver => winner != null;
  int targetArm(int p) => (homes[p] + 3) % 6;
  int targetTip(int p) => HalmaBoard.tips[targetArm(p)];

  /// Holes reachable by the piece on [from], with the way there
  /// (from … to).
  Map<int, List<int>> destinations(int from) {
    final result = <int, List<int>>{};
    for (final d in HalmaBoard.dirs) {
      final n = HalmaBoard.neighbour(from, d);
      if (n != null && owner[n] < 0) result[n] = [from, n];
    }
    // Jump chains (breadth first, so the shortest chain is kept).
    final queue = [
      [from],
    ];
    final seen = {from};
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final at = path.last;
      for (final d in HalmaBoard.dirs) {
        final over = HalmaBoard.neighbour(at, d);
        final to = HalmaBoard.neighbour(at, d, 2);
        if (over == null || to == null) continue;
        if (owner[over] < 0 || owner[to] >= 0 || !seen.add(to)) continue;
        final next = [...path, to];
        result[to] ??= next;
        queue.add(next);
      }
    }
    return result;
  }

  bool isValid(List<int> path) {
    if (isOver || path.length < 2) return false;
    if (owner[path.first] != current) return false;
    final occupied = List.of(owner)..[path.first] = -1;
    if (path.length == 2) {
      if (HalmaBoard.distance(path[0], path[1]) == 1) {
        return occupied[path[1]] < 0;
      }
    }
    final visited = {path.first};
    for (var i = 0; i + 1 < path.length; i++) {
      final a = path[i], b = path[i + 1];
      if (b < 0 || b >= owner.length || occupied[b] >= 0) return false;
      if (!visited.add(b)) return false;
      final (x1, y1, z1) = HalmaBoard.cells[a];
      final (x2, y2, z2) = HalmaBoard.cells[b];
      final dx = x2 - x1, dy = y2 - y1, dz = z2 - z1;
      if (dx.isOdd || dy.isOdd || dz.isOdd) return false;
      final d = (dx ~/ 2, dy ~/ 2, dz ~/ 2);
      if (!HalmaBoard.dirs.contains(d)) return false;
      final over = HalmaBoard.neighbour(a, d)!;
      if (occupied[over] < 0) return false;
    }
    return true;
  }

  bool move(List<int> path) {
    if (!isValid(path)) return false;
    owner[path.last] = current;
    owner[path.first] = -1;
    moves.add(path);
    if (_hasWon(current)) {
      winner = current;
    } else {
      _next();
    }
    return true;
  }

  void _next() {
    for (var i = 0; i < players; i++) {
      current = (current + 1) % players;
      if (_canMove(current)) return;
    }
  }

  bool _canMove(int p) {
    for (var c = 0; c < owner.length; c++) {
      if (owner[c] == p && destinations(c).isNotEmpty) return true;
    }
    return false;
  }

  /// All holes of the target arm are taken, at least one by the player
  /// (so nobody can block a target by sitting in it).
  bool _hasWon(int p) {
    final target = HalmaBoard.arms[targetArm(p)];
    if (target.any((c) => owner[c] < 0)) return false;
    return target.any((c) => owner[c] == p);
  }

  int piecesHome(int p) =>
      HalmaBoard.arms[targetArm(p)].where((c) => owner[c] == p).length;
}

/// Greedy computer: the move that brings a piece furthest towards the
/// target tip, preferring pieces that lag behind.
class HalmaAi {
  HalmaAi([Random? random]) : _random = random ?? Random();
  final Random _random;

  List<int> choose(HalmaGame g) {
    final p = g.current;
    final tip = g.targetTip(p);
    final target = HalmaBoard.arms[g.targetArm(p)].toSet();
    List<int>? best;
    var bestScore = double.negativeInfinity;
    for (var c = 0; c < g.owner.length; c++) {
      if (g.owner[c] != p) continue;
      final before = HalmaBoard.distance(c, tip);
      g.destinations(c).forEach((to, path) {
        final after = HalmaBoard.distance(to, tip);
        var score = (before - after) + before * 0.15;
        // Do not leave the target again.
        if (target.contains(c) && !target.contains(to)) score -= 20;
        score += _random.nextDouble() * 0.1;
        if (score > bestScore) {
          bestScore = score;
          best = path;
        }
      });
    }
    return best!;
  }
}
