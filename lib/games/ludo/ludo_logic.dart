import 'dart:math';

/// Mensch ärgere dich nicht for 2–4 players.
///
/// Every player has 4 pieces. A piece's position counts from its own start
/// field: -1 = in the house, 0–39 = on the track, 40–43 = in the goal.
/// Rules: a 6 brings a piece out (and must, if possible), the start field
/// must be cleared, a 6 rolls again, three tries for a 6 while no piece can
/// move, landing on another piece sends it home, no jumping in the goal.
class LudoGame {
  LudoGame({this.players = 4, int first = 0})
    : pieces = List.generate(players, (_) => List.filled(4, -1)) {
    current = first % players;
    _startTurn();
  }

  /// Replays saved events (see [events]).
  factory LudoGame.replay(int players, List<dynamic> events, {int first = 0}) {
    final g = LudoGame(players: players, first: first);
    for (final e in events.cast<List<dynamic>>()) {
      final ok = e[0] == 'r' ? g.roll(e[1] as int) : g.move(e[1] as int);
      if (!ok) throw FormatException('illegal event $e');
    }
    return g;
  }

  static const trackLength = 40;
  static const goalStart = 40;
  static const finish = 43;

  final int players;
  final List<List<int>> pieces;
  int current = 0;

  /// The die of the current turn, null while the player has to roll.
  int? die;

  /// Rolls left this turn (three tries while no piece can move).
  int triesLeft = 1;
  int? winner;

  /// Pieces sent home by the last move (player, piece) – for effects.
  (int, int)? lastCapture;

  /// ['r', value] and ['m', piece] in order, for saving.
  final List<List<Object>> events = [];

  bool get isOver => winner != null;
  bool get mustRoll => !isOver && die == null;

  /// Board side of a player: two players sit opposite each other.
  int sideOf(int player) => players == 2 ? player * 2 : player;

  /// Field on the 40 field track (0 = start field of side 0).
  int absolute(int player, int pos) => (sideOf(player) * 10 + pos) % 40;

  /// Whether no piece can move with any number: all at home or packed at
  /// the end of the goal. Then a player gets three tries for a 6.
  bool _stuck(int player) {
    final p = pieces[player];
    if (p.any((x) => x >= 0 && x < goalStart)) return false;
    final inGoal = p.where((x) => x >= goalStart).toList()..sort();
    for (var i = 0; i < inGoal.length; i++) {
      if (inGoal[i] != finish - (inGoal.length - 1 - i)) return false;
    }
    return true;
  }

  /// Start of a turn.
  void _startTurn() {
    die = null;
    triesLeft = _stuck(current) ? 3 : 1;
  }

  bool _ownAt(int player, int pos) => pieces[player].contains(pos);

  /// Where a piece would go with [roll], or null if it cannot move.
  int? target(int player, int piece, int roll) {
    final pos = pieces[player][piece];
    if (pos >= finish) return null;
    if (pos < 0) {
      if (roll != 6 || _ownAt(player, 0)) return null;
      return 0;
    }
    final t = pos + roll;
    if (t > finish) return null;
    if (t >= goalStart) {
      // No jumping over own pieces in the goal.
      for (var g = max(pos + 1, goalStart); g <= t; g++) {
        if (_ownAt(player, g)) return null;
      }
      return t;
    }
    if (_ownAt(player, t)) return null;
    return t;
  }

  /// Pieces the current player may move with the current die.
  List<int> movable() {
    final d = die;
    if (d == null || isOver) return const [];
    final all = [
      for (var i = 0; i < 4; i++)
        if (target(current, i, d) != null) i,
    ];
    final p = pieces[current];
    // A 6 must bring a piece out.
    if (d == 6) {
      final out = all.where((i) => p[i] < 0).toList();
      if (out.isNotEmpty) return out;
    }
    // The start field must be cleared while pieces wait in the house.
    if (p.contains(-1)) {
      final onStart = all.where((i) => p[i] == 0).toList();
      if (onStart.isNotEmpty) return onStart;
    }
    return all;
  }

  /// Rolls [value] for the current player. False if not allowed now.
  bool roll(int value) {
    if (!mustRoll || value < 1 || value > 6) return false;
    die = value;
    events.add(['r', value]);
    if (movable().isEmpty) {
      triesLeft--;
      if (value == 6) {
        // Roll again.
        die = null;
        triesLeft = max(triesLeft, 1);
      } else if (triesLeft > 0) {
        die = null;
      } else {
        _next();
      }
    }
    return true;
  }

  /// Moves a piece of the current player with the current die.
  bool move(int piece) {
    final d = die;
    if (d == null || !movable().contains(piece)) return false;
    final t = target(current, piece, d)!;
    pieces[current][piece] = t;
    events.add(['m', piece]);
    lastCapture = null;
    if (t < goalStart) {
      final field = absolute(current, t);
      for (var o = 0; o < players; o++) {
        if (o == current) continue;
        for (var i = 0; i < 4; i++) {
          final op = pieces[o][i];
          if (op >= 0 && op < goalStart && absolute(o, op) == field) {
            pieces[o][i] = -1;
            lastCapture = (o, i);
          }
        }
      }
    }
    if (pieces[current].every((x) => x >= goalStart)) {
      winner = current;
      die = null;
      return true;
    }
    if (d == 6) {
      die = null;
      triesLeft = 1;
    } else {
      _next();
    }
    return true;
  }

  void _next() {
    current = (current + 1) % players;
    _startTurn();
  }

  LudoGame copy() {
    final g = LudoGame(players: players, first: current);
    for (var p = 0; p < players; p++) {
      g.pieces[p].setAll(0, pieces[p]);
    }
    g
      ..current = current
      ..die = die
      ..triesLeft = triesLeft
      ..winner = winner;
    return g;
  }
}

/// Computer player: finish and capture first, bring pieces out, get out of
/// danger, otherwise move the piece furthest ahead.
class LudoAi {
  LudoAi([Random? random]) : _random = random ?? Random();
  final Random _random;

  int choose(LudoGame g) {
    final options = g.movable();
    var best = options.first;
    var bestScore = -1e9;
    final me = g.current, d = g.die!;
    for (final i in options) {
      final from = g.pieces[me][i];
      final to = g.target(me, i, d)!;
      var score = to / 40.0;
      if (to >= LudoGame.goalStart) score += 10 + to - LudoGame.goalStart;
      if (from < 0) score += 6;
      if (to < LudoGame.goalStart) {
        final field = g.absolute(me, to);
        // Capture.
        for (var o = 0; o < g.players; o++) {
          if (o == me) continue;
          for (final op in g.pieces[o]) {
            if (op >= 0 &&
                op < LudoGame.goalStart &&
                g.absolute(o, op) == field) {
              score += 8 + op / 10;
            }
          }
        }
        score -= 4 * _danger(g, me, field);
      }
      if (from >= 0 && from < LudoGame.goalStart) {
        score += 3 * _danger(g, me, g.absolute(me, from));
      }
      score += _random.nextDouble() * 0.5;
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /// How many opponent pieces stand 1–6 fields behind [field].
  static int _danger(LudoGame g, int me, int field) {
    var n = 0;
    for (var o = 0; o < g.players; o++) {
      if (o == me) continue;
      for (final op in g.pieces[o]) {
        if (op < 0 || op >= LudoGame.goalStart) continue;
        final dist = (field - g.absolute(o, op) + 40) % 40;
        if (dist >= 1 && dist <= 6) n++;
      }
    }
    return n;
  }
}
