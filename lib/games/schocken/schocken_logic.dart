import 'dart:math';

/// A finished throw of three dice and how it ranks.
class SchockenThrow {
  SchockenThrow(List<int> dice) : dice = (List.of(dice)..sort((a, b) => b - a));

  /// Highest first.
  final List<int> dice;

  int get _ones => dice.where((d) => d == 1).length;

  /// Higher is better: Schock aus 1000, Schock 2–6 902–906, General
  /// 801–806, Straße 703–706 (by its highest die), otherwise the dice read
  /// as a number (6-4-2 = 642).
  int get score {
    final [a, b, c] = dice;
    if (_ones == 3) return 1000;
    if (_ones == 2) return 900 + a;
    if (a == b && b == c) return 800 + a;
    if (a == b + 1 && b == c + 1) return 700 + a;
    return a * 100 + b * 10 + c;
  }

  bool get isSchockAus => score == 1000;

  /// Lids the loser of the round gets when this is the best throw.
  int get lids {
    final s = score;
    if (s == 1000) return 13;
    if (s > 900) return s - 900;
    if (s > 800) return 3;
    if (s > 700) return 2;
    return 1;
  }

  String get name {
    final s = score;
    final [a, b, c] = dice;
    if (s == 1000) return 'Schock aus';
    if (s > 900) return 'Schock $a';
    if (s > 800) return 'General ($a)';
    if (s > 700) return 'Straße $c-$b-$a';
    return '$a-$b-$c';
  }
}

/// A player's throw in the current round.
class SchockenResult {
  const SchockenResult(this.seat, this.result, this.rolls);
  final int seat;
  final SchockenThrow result;
  final int rolls;
}

/// What happened in the last finished round (for the screen).
class SchockenRoundEnd {
  const SchockenRoundEnd({
    required this.best,
    required this.worst,
    required this.bestThrow,
    required this.worstThrow,
    required this.lids,
    required this.fromPot,
    required this.halfLost,
  });
  final int best;
  final int worst;
  final SchockenThrow bestThrow;
  final SchockenThrow worstThrow;
  final int lids;
  final bool fromPot;

  /// The worst player lost the half with this round.
  final bool halfLost;
}

/// Schocken with three dice and 13 lids ("Deckel").
///
/// Every round each player throws once, up to three times; the first
/// player of the round sets how often the others may throw. After a throw
/// any dice may be kept, two sixes may be turned into a one. The worst
/// throw of the round takes lids: first from the pot, once it is empty from
/// the best player. Players without lids are then safe for this half. Who
/// has all 13 lids (or loses against a Schock aus) loses the half. Two
/// halves are played; if they have different losers, these two play the
/// final. Equal throws: fewer throws are better, then who threw first.
///
/// Played through [apply] with plain events so it can be sent and saved:
/// `['new']` starts a game, `['r', d0, d1, d2]` rolls (held dice keep
/// their values), `['h', i]` keeps or frees die i, `['t']` turns two sixes
/// into a one, `['s']` ends the turn.
class SchockenGame {
  SchockenGame({required this.players, this.first = 0});

  factory SchockenGame.replay(int players, List events, {int first = 0}) {
    final g = SchockenGame(players: players, first: first);
    for (final e in events) {
      g.apply(List.from(e as List));
    }
    return g;
  }

  static const totalLids = 13;

  final int players;
  final int first;
  final List<List> events = [];

  int match = -1;

  /// 1, 2 or 3 (the final).
  int half = 1;
  final List<int> halfLosers = [];
  int pot = totalLids;
  List<int> lids = [];

  /// Who plays in this half (all, or the two half losers in the final).
  List<bool> inHalf = [];

  /// Who still plays in this half (no lids once the pot is empty = safe).
  List<bool> active = [];

  List<int> order = [];
  int pos = 0;
  int maxRolls = 3;
  final List<SchockenResult> results = [];

  List<int> dice = [1, 1, 1];
  List<bool> held = [false, false, false];
  int rolls = 0;

  SchockenRoundEnd? lastRound;
  int? loser;

  bool get started => match >= 0;
  bool get isOver => loser != null;
  int get current => order[pos];
  int? get toMove => !started || isOver ? null : current;
  bool get isStarter => pos == 0;
  int get starter => order.first;
  bool get canRoll => started && !isOver && rolls < maxRolls;
  bool get canStop => started && !isOver && rolls > 0;
  bool get canHold => started && !isOver && rolls > 0 && rolls < maxRolls;
  bool get canTurn => canHold && dice.where((d) => d == 6).length >= 2;

  SchockenThrow get currentThrow => SchockenThrow(dice);

  String get halfName => switch (half) {
    1 => '1. Hälfte',
    2 => '2. Hälfte',
    _ => 'Finale',
  };

  /// Whether [a] beats [b] (both in this round, [a] may be unfinished).
  static bool beats(SchockenResult a, SchockenResult b, List<int> order) {
    final sa = a.result.score, sb = b.result.score;
    if (sa != sb) return sa > sb;
    if (a.rolls != b.rolls) return a.rolls < b.rolls;
    return order.indexOf(a.seat) < order.indexOf(b.seat);
  }

  /// The worst result so far in this round (null before the first).
  SchockenResult? get worstSoFar => results.isEmpty
      ? null
      : results.reduce((x, y) => beats(x, y, order) ? y : x);

  bool apply(List e) {
    switch (e) {
      case ['new']:
        if (started && !isOver) return false;
        _newGame();
      case ['r', final int a, final int b, final int c]:
        if (!canRoll) return false;
        final next = [a, b, c];
        for (var i = 0; i < 3; i++) {
          if (next[i] < 1 || next[i] > 6) return false;
          if (rolls > 0 && held[i] && next[i] != dice[i]) return false;
        }
        if (rolls == 0) held = [false, false, false];
        dice = next;
        rolls++;
        if (rolls == maxRolls) _endTurn();
      case ['h', final int i]:
        if (!canHold || i < 0 || i > 2) return false;
        held[i] = !held[i];
      case ['t']:
        if (!canTurn) return false;
        // A free six if there is one, so kept dice stay as they are.
        var i = -1;
        for (var k = 0; k < 3; k++) {
          if (dice[k] == 6 && (i == -1 || held[i] && !held[k])) i = k;
        }
        dice[i] = 1;
        held[i] = true;
      case ['s']:
        if (!canStop) return false;
        _endTurn();
      default:
        return false;
    }
    events.add(e);
    return true;
  }

  void _newGame() {
    match++;
    half = 1;
    halfLosers.clear();
    lastRound = null;
    loser = null;
    _newHalf(List.filled(players, true), (first + match) % players);
  }

  void _newHalf(List<bool> who, int starter) {
    pot = totalLids;
    lids = List.filled(players, 0);
    inHalf = who;
    active = List.of(who);
    _newRound(starter);
  }

  void _newRound(int starter) {
    order = [
      for (var k = 0; k < players; k++)
        if (active[(starter + k) % players]) (starter + k) % players,
    ];
    pos = 0;
    maxRolls = 3;
    results.clear();
    _newTurn();
  }

  void _newTurn() {
    dice = [1, 1, 1];
    held = [false, false, false];
    rolls = 0;
  }

  void _endTurn() {
    results.add(SchockenResult(current, currentThrow, rolls));
    if (isStarter) maxRolls = rolls;
    if (pos + 1 < order.length) {
      pos++;
      _newTurn();
      return;
    }
    _endRound();
  }

  void _endRound() {
    var best = results.first, worst = results.first;
    for (final r in results.skip(1)) {
      if (beats(r, best, order)) best = r;
      if (!beats(r, worst, order)) worst = r;
    }
    final w = worst.seat;
    final fromPot = pot > 0;
    var n = best.result.lids;
    var halfLost = best.result.isSchockAus;
    if (!halfLost) {
      if (fromPot) {
        n = min(n, pot);
        pot -= n;
      } else {
        n = min(n, lids[best.seat]);
        lids[best.seat] -= n;
      }
      lids[w] += n;
      if (pot == 0) {
        for (var p = 0; p < players; p++) {
          if (lids[p] == 0) active[p] = false;
        }
      }
      halfLost = lids[w] == totalLids;
    }
    lastRound = SchockenRoundEnd(
      best: best.seat,
      worst: w,
      bestThrow: best.result,
      worstThrow: worst.result,
      lids: n,
      fromPot: fromPot,
      halfLost: halfLost,
    );
    if (halfLost) {
      _endHalf(w);
    } else {
      _newRound(w);
    }
  }

  void _endHalf(int l) {
    halfLosers.add(l);
    if (half == 3 || (half == 2 && halfLosers.first == l)) {
      loser = l;
      return;
    }
    half++;
    final who = half == 2
        ? List.filled(players, true)
        : [for (var p = 0; p < players; p++) halfLosers.contains(p)];
    _newHalf(who, l);
  }
}

/// Computer player: keeps ones (and pairs for a General), turns sixes,
/// and stops as soon as it is not the worst of the round any more.
class SchockenAi {
  List choose(SchockenGame g, Random random) {
    if (g.rolls == 0) return _roll(g, random);
    final t = g.currentThrow;
    if (g.canTurn && t.score < 800) return ['t'];
    if (g.canStop && _goodEnough(g, t)) return ['s'];
    final want = _holds(g.dice);
    for (var i = 0; i < 3; i++) {
      if (g.held[i] != want[i]) return ['h', i];
    }
    return _roll(g, random);
  }

  List _roll(SchockenGame g, Random random) => [
    'r',
    for (var i = 0; i < 3; i++)
      g.rolls > 0 && g.held[i] ? g.dice[i] : random.nextInt(6) + 1,
  ];

  bool _goodEnough(SchockenGame g, SchockenThrow t) {
    if (t.score >= 900) return true;
    if (g.isStarter) {
      return t.score >= 800 || (g.rolls >= 2 && t.score >= 700);
    }
    final worst = g.worstSoFar;
    if (worst == null) return t.score >= 700;
    final mine = SchockenResult(g.current, t, g.rolls);
    return SchockenGame.beats(mine, worst, g.order);
  }

  /// Ones stay; without ones a pair of 4, 5 or 6 stays (General chance).
  static List<bool> _holds(List<int> dice) {
    if (dice.contains(1)) return [for (final d in dice) d == 1];
    for (final v in [6, 5, 4]) {
      if (dice.where((d) => d == v).length >= 2) {
        return [for (final d in dice) d == v];
      }
    }
    return [false, false, false];
  }
}
