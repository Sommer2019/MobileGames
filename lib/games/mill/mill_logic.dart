import 'dart:math';

/// Mühle (Nine Men's Morris).
///
/// Points 0..23: three rings (outer 0–7, middle 8–15, inner 16–23), each
/// numbered clockwise from the top left corner. Odd points are the middle
/// of a side and connect to the neighbouring ring.
enum MillPhase { placing, moving }

class MillGame {
  MillGame();

  /// A saved game (see [toJson]).
  factory MillGame.fromJson(Map<String, dynamic> j) {
    final g = MillGame();
    g.board.setAll(0, (j['board'] as List).cast<int>());
    g.toPlace.setAll(0, (j['toPlace'] as List).cast<int>());
    final last = j['last'] as List?;
    g
      ..turn = j['turn'] as int
      ..mustRemove = j['mustRemove'] as bool
      ..movesWithoutRemoval = j['quiet'] as int
      ..lastMove = last == null ? null : (last[0] as int, last[1] as int);
    return g;
  }

  Map<String, dynamic> toJson() => {
    'board': board,
    'toPlace': toPlace,
    'turn': turn,
    'mustRemove': mustRemove,
    'quiet': movesWithoutRemoval,
    if (lastMove case final m?) 'last': [m.$1, m.$2],
  };

  /// Nothing happened yet.
  bool get isFresh => toPlace[1] == 9 && toPlace[2] == 9;

  static final List<List<int>> neighbours = _buildNeighbours();
  static final List<List<int>> mills = _buildMills();

  static List<List<int>> _buildNeighbours() {
    final n = List.generate(24, (_) => <int>[]);
    void link(int a, int b) {
      n[a].add(b);
      n[b].add(a);
    }

    for (var ring = 0; ring < 3; ring++) {
      for (var i = 0; i < 8; i++) {
        link(ring * 8 + i, ring * 8 + (i + 1) % 8);
      }
    }
    for (final k in [1, 3, 5, 7]) {
      link(k, k + 8);
      link(k + 8, k + 16);
    }
    return n;
  }

  static List<List<int>> _buildMills() => [
    for (var ring = 0; ring < 3; ring++)
      for (final s in [0, 2, 4, 6])
        [ring * 8 + s, ring * 8 + s + 1, ring * 8 + (s + 2) % 8],
    for (final k in [1, 3, 5, 7]) [k, k + 8, k + 16],
  ];

  /// 0 = empty, 1 = white, 2 = black.
  final List<int> board = List.filled(24, 0);
  final List<int> toPlace = [0, 9, 9];
  int turn = 1;
  int winner = 0;
  bool draw = false;

  /// The player to move just closed a mill and must remove a stone.
  bool mustRemove = false;
  int movesWithoutRemoval = 0;
  (int, int)? lastMove;

  bool get isOver => winner != 0 || draw;
  int opponent(int p) => 3 - p;
  int stones(int p) => board.where((x) => x == p).length;

  MillPhase phaseOf(int p) =>
      toPlace[p] > 0 ? MillPhase.placing : MillPhase.moving;
  bool canFly(int p) => phaseOf(p) == MillPhase.moving && stones(p) == 3;

  bool inMill(int point) {
    final p = board[point];
    if (p == 0) return false;
    return mills.any((m) => m.contains(point) && m.every((x) => board[x] == p));
  }

  bool _closesMill(int point, int player) => mills.any(
    (m) =>
        m.contains(point) && m.every((x) => x == point || board[x] == player),
  );

  /// Stones of the opponent that may be removed now.
  List<int> removable() {
    final opp = opponent(turn);
    final all = [
      for (var i = 0; i < 24; i++)
        if (board[i] == opp) i,
    ];
    final free = all.where((i) => !inMill(i)).toList();
    return free.isNotEmpty ? free : all;
  }

  bool canPlace(int point) =>
      !isOver &&
      !mustRemove &&
      phaseOf(turn) == MillPhase.placing &&
      board[point] == 0;

  List<int> targets(int from) {
    if (isOver || mustRemove || phaseOf(turn) != MillPhase.moving) {
      return const [];
    }
    if (board[from] != turn) return const [];
    if (canFly(turn)) {
      return [
        for (var i = 0; i < 24; i++)
          if (board[i] == 0) i,
      ];
    }
    return neighbours[from].where((n) => board[n] == 0).toList();
  }

  bool place(int point) {
    if (!canPlace(point)) return false;
    board[point] = turn;
    toPlace[turn]--;
    lastMove = (point, point);
    _afterAction(point);
    return true;
  }

  bool move(int from, int to) {
    if (!targets(from).contains(to)) return false;
    board[from] = 0;
    board[to] = turn;
    lastMove = (from, to);
    movesWithoutRemoval++;
    _afterAction(to);
    return true;
  }

  bool remove(int point) {
    if (!mustRemove || !removable().contains(point)) return false;
    board[point] = 0;
    mustRemove = false;
    movesWithoutRemoval = 0;
    _endTurn();
    return true;
  }

  void _afterAction(int point) {
    if (inMill(point) && removable().isNotEmpty) {
      mustRemove = true;
      return;
    }
    _endTurn();
  }

  void _endTurn() {
    final opp = opponent(turn);
    turn = opp;
    // Losing conditions for the player that has to move now.
    if (phaseOf(opp) == MillPhase.moving && stones(opp) + toPlace[opp] < 3) {
      winner = 3 - opp;
    } else if (!_hasMove(opp)) {
      winner = 3 - opp;
    } else if (movesWithoutRemoval >= 100) {
      draw = true;
    }
  }

  bool _hasMove(int p) {
    if (phaseOf(p) == MillPhase.placing || canFly(p)) return true;
    for (var i = 0; i < 24; i++) {
      if (board[i] == p && neighbours[i].any((n) => board[n] == 0)) return true;
    }
    return false;
  }

  MillGame copy() {
    final g = MillGame();
    g.board.setAll(0, board);
    g.toPlace.setAll(0, toPlace);
    g
      ..turn = turn
      ..winner = winner
      ..draw = draw
      ..mustRemove = mustRemove
      ..movesWithoutRemoval = movesWithoutRemoval;
    return g;
  }

  /// Computer opponent: closes mills, blocks the opponent's mills, removes
  /// dangerous stones, otherwise plays randomly.
  /// Returns ('place', p, -1), ('move', from, to) or ('remove', p, -1).
  (String, int, int)? aiAction([Random? random]) {
    final r = random ?? Random();
    if (isOver) return null;
    final me = turn, opp = opponent(turn);
    if (mustRemove) {
      final options = removable();
      // Prefer stones that are one step away from a mill.
      options.sort((a, b) => _threat(b, opp).compareTo(_threat(a, opp)));
      final top = options
          .where((x) => _threat(x, opp) == _threat(options.first, opp))
          .toList();
      return ('remove', top[r.nextInt(top.length)], -1);
    }
    if (phaseOf(me) == MillPhase.placing) {
      final empty = [
        for (var i = 0; i < 24; i++)
          if (board[i] == 0) i,
      ];
      final win = empty.where((p) => _closesMill(p, me)).toList();
      if (win.isNotEmpty) return ('place', win[r.nextInt(win.length)], -1);
      final block = empty.where((p) => _closesMill(p, opp)).toList();
      if (block.isNotEmpty) {
        return ('place', block[r.nextInt(block.length)], -1);
      }
      // Middle points have the most neighbours.
      final good = empty.where((p) => p.isOdd && p >= 8 && p < 16).toList();
      final pool = good.isNotEmpty && r.nextBool() ? good : empty;
      return ('place', pool[r.nextInt(pool.length)], -1);
    }
    final moves = <(int, int)>[
      for (var i = 0; i < 24; i++)
        if (board[i] == me)
          for (final t in targets(i)) (i, t),
    ];
    if (moves.isEmpty) return null;
    var best = -1e9;
    (int, int)? choice;
    for (final (f, t) in moves) {
      final g = copy();
      g.board[f] = 0;
      var score = 0.0;
      if (g._closesMill(t, me)) score += 10;
      if (_closesMill(t, opp)) score += 4; // blocks a mill
      g.board[t] = me;
      // Do not open our position so the opponent can close a mill.
      for (var i = 0; i < 24; i++) {
        if (g.board[i] == 0 &&
            g._closesMill(i, opp) &&
            MillGame.neighbours[i].any((n) => g.board[n] == opp)) {
          score -= 3;
        }
      }
      score += r.nextDouble();
      if (score > best) {
        best = score;
        choice = (f, t);
      }
    }
    return ('move', choice!.$1, choice.$2);
  }

  int _threat(int point, int player) => mills
      .where((m) => m.contains(point))
      .map((m) => m.where((x) => board[x] == player).length)
      .fold(0, max);
}
