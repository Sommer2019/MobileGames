import 'dart:math';

/// "Stapelfix": build piles from 1 to 12 together, first to empty the own
/// stock pile wins.
///
/// Cards 0–143 are the numbers 1–12 (twelve of each), the rest are jokers.
/// Played through [apply]: `['deal', seed, jokers]`, `['b', source, pile]`
/// (source: a hand card id, −1 the stock, −2 … −5 a discard pile) and
/// `['x', card, discardPile]` to end the turn (`['x', -1, -1]` with an
/// empty hand).
class StapelfixGame {
  StapelfixGame({required this.players, this.first = 0});

  factory StapelfixGame.replay(int players, List events, {int first = 0}) {
    final g = StapelfixGame(players: players, first: first);
    for (final e in events) {
      g.apply(List.from(e as List));
    }
    return g;
  }

  static const handSize = 5;
  static const numbers = 144;

  final int players;
  final int first;
  final List<List> events = [];

  int match = -1;
  int seed = 0;
  int jokers = 18;

  List<List<int>> stock = [];
  List<List<int>> hands = [];
  List<List<List<int>>> discards = [];
  List<List<int>> build = [];
  List<int> pile = [];
  List<int> done = [];
  int current = 0;
  int? winner;
  int _reshuffles = 0;

  bool get dealt => match >= 0;
  bool get isOver => winner != null;
  int? get toMove => !dealt || isOver ? null : current;
  int get stockSize => players <= 4 ? 20 : 15;

  static bool isJoker(int card) => card >= numbers;
  static int value(int card) => isJoker(card) ? 0 : card ~/ 12 + 1;

  /// The value the next card on build pile [i] has.
  int need(int i) => build[i].length + 1;

  bool fits(int card, int i) => isJoker(card) || value(card) == need(i);

  int? stockTop(int p) => stock[p].isEmpty ? null : stock[p].last;
  int? discardTop(int p, int i) =>
      discards[p][i].isEmpty ? null : discards[p][i].last;

  /// The card a source stands for (see class comment), or null.
  int? cardOf(int source) {
    if (source >= 0) return hands[current].contains(source) ? source : null;
    if (source == -1) return stockTop(current);
    final i = -2 - source;
    if (i < 0 || i > 3) return null;
    return discardTop(current, i);
  }

  bool canBuild(int source, int i) {
    if (!dealt || isOver || i < 0 || i > 3) return false;
    final c = cardOf(source);
    return c != null && fits(c, i);
  }

  bool apply(List e) {
    switch (e) {
      case ['deal', final int s, final int j]:
        if (dealt && !isOver) return false;
        _deal(s, j);
      case ['b', final int source, final int i]:
        if (!canBuild(source, i)) return false;
        _build(source, i);
      case ['x', final int card, final int i]:
        if (!dealt || isOver) return false;
        final hand = hands[current];
        if (card == -1) {
          if (hand.isNotEmpty) return false;
        } else {
          if (!hand.contains(card) || i < 0 || i > 3) return false;
          hand.remove(card);
          discards[current][i].add(card);
        }
        current = (current + 1) % players;
        _refill(current);
      default:
        return false;
    }
    events.add(e);
    return true;
  }

  void _deal(int s, int j) {
    match++;
    seed = s;
    jokers = j;
    pile = List.generate(numbers + j, (i) => i)..shuffle(Random(s));
    stock = [
      for (var p = 0; p < players; p++)
        [for (var k = 0; k < stockSize; k++) pile.removeLast()],
    ];
    hands = [for (var p = 0; p < players; p++) <int>[]];
    discards = [
      for (var p = 0; p < players; p++) [<int>[], <int>[], <int>[], <int>[]],
    ];
    build = [<int>[], <int>[], <int>[], <int>[]];
    done = [];
    winner = null;
    _reshuffles = 0;
    current = (first + match) % players;
    _refill(current);
  }

  void _refill(int p) {
    final hand = hands[p];
    while (hand.length < handSize) {
      if (pile.isEmpty) {
        if (done.isEmpty) return;
        pile = done..shuffle(Random(seed * 13 + ++_reshuffles));
        done = [];
      }
      hand.add(pile.removeLast());
    }
  }

  void _build(int source, int i) {
    final p = current;
    final int card;
    if (source >= 0) {
      card = source;
      hands[p].remove(card);
    } else if (source == -1) {
      card = stock[p].removeLast();
    } else {
      card = discards[p][-2 - source].removeLast();
    }
    build[i].add(card);
    if (build[i].length == 12) {
      done.addAll(build[i]);
      build[i] = [];
    }
    if (stock[p].isEmpty) {
      winner = p;
      return;
    }
    if (hands[p].isEmpty) _refill(p);
  }
}

/// Computer player: plays its stock card whenever it can, also through a
/// short chain of hand and discard cards; otherwise gets rid of fitting
/// cards and discards sensibly.
class StapelfixAi {
  List choose(StapelfixGame g) {
    final p = g.current;
    final top = g.stockTop(p)!;
    // 1. Stock card fits.
    for (var i = 0; i < 4; i++) {
      if (g.fits(top, i) &&
          (!StapelfixGame.isJoker(top) || i == _jokerPile(g))) {
        return ['b', -1, i];
      }
    }
    // 2. A chain that frees the stock card.
    final chain = _chain(g, top);
    if (chain != null) return chain;
    // 3. Discard tops, then hand numbers that fit (no jokers).
    for (var d = 0; d < 4; d++) {
      final c = g.discardTop(p, d);
      if (c == null || StapelfixGame.isJoker(c)) continue;
      for (var i = 0; i < 4; i++) {
        if (g.fits(c, i)) return ['b', -2 - d, i];
      }
    }
    for (final c in g.hands[p]) {
      if (StapelfixGame.isJoker(c)) continue;
      for (var i = 0; i < 4; i++) {
        if (g.fits(c, i)) return ['b', c, i];
      }
    }
    // 4. Discard.
    final hand = g.hands[p];
    if (hand.isEmpty) return ['x', -1, -1];
    final numbers = hand.where((c) => !StapelfixGame.isJoker(c)).toList();
    final pool = numbers.isEmpty ? hand : numbers;
    final card = pool.reduce(
      (a, b) => StapelfixGame.value(a) >= StapelfixGame.value(b) ? a : b,
    );
    final v = StapelfixGame.value(card);
    final piles = g.discards[p];
    int? target;
    for (var i = 0; i < 4 && target == null; i++) {
      final t = g.discardTop(p, i);
      if (t != null && StapelfixGame.value(t) == v) target = i;
    }
    for (var i = 0; i < 4 && target == null; i++) {
      final t = g.discardTop(p, i);
      if (t != null && StapelfixGame.value(t) == v + 1) target = i;
    }
    for (var i = 0; i < 4 && target == null; i++) {
      if (piles[i].isEmpty) target = i;
    }
    target ??= List.generate(4, (i) => i).reduce(
      (a, b) =>
          StapelfixGame.value(g.discardTop(p, a)!) >=
              StapelfixGame.value(g.discardTop(p, b)!)
          ? a
          : b,
    );
    return ['x', card, target];
  }

  /// Joker from the stock goes where it brings the most.
  static int _jokerPile(StapelfixGame g) {
    var best = 0;
    for (var i = 1; i < 4; i++) {
      if (g.build[i].length > g.build[best].length) best = i;
    }
    return best;
  }

  /// First step of up to four plays (hand and discard tops) after which
  /// the stock card [top] fits.
  List? _chain(StapelfixGame g, int top) {
    final p = g.current;
    final want = StapelfixGame.value(top);
    // Cards available: (source, card); discard piles offer their top only
    // (deeper cards would need tracking, kept simple).
    final sources = <(int, int)>[
      for (final c in g.hands[p]) (c, c),
      for (var d = 0; d < 4; d++)
        if (g.discardTop(p, d) != null) (-2 - d, g.discardTop(p, d)!),
    ];
    for (var i = 0; i < 4; i++) {
      final have = g.build[i].length; // value on top
      final gap = want - 1 - have; // cards needed in between
      if (gap <= 0 || gap > 4) continue;
      // Pick numbers have+1 … want−1, jokers fill gaps.
      final used = <int>{};
      List? firstStep;
      var ok = true;
      for (var v = have + 1; v < want; v++) {
        (int, int)? pick;
        for (final s in sources) {
          if (!used.contains(s.$1) && StapelfixGame.value(s.$2) == v) {
            pick = s;
            break;
          }
        }
        pick ??= sources
            .where((s) => !used.contains(s.$1) && StapelfixGame.isJoker(s.$2))
            .firstOrNull;
        if (pick == null) {
          ok = false;
          break;
        }
        used.add(pick.$1);
        firstStep ??= ['b', pick.$1, i];
      }
      if (ok && firstStep != null) return firstStep;
    }
    return null;
  }
}
