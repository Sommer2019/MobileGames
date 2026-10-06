import 'dart:math';

/// Card kinds: 0–9 numbers, then the action cards.
const kSkip = 10, kReverse = 11, kDraw2 = 12, kWild = 13, kWild4 = 14;

/// The 108 cards: per colour one 0, two each of 1–9, skip, reverse and +2;
/// then four colour wishes and four +4.
class LcCard {
  LcCard._();

  static const count = 108;

  /// Colour 0–3, or −1 for wild cards.
  static int color(int id) => id < 100 ? id ~/ 25 : -1;

  static int kind(int id) {
    if (id >= 104) return kWild4;
    if (id >= 100) return kWild;
    final k = id % 25;
    if (k == 0) return 0;
    if (k <= 18) return (k + 1) ~/ 2;
    if (k <= 20) return kSkip;
    if (k <= 22) return kReverse;
    return kDraw2;
  }

  static bool isWild(int id) => id >= 100;
  static bool isDraw(int id) => kind(id) == kDraw2 || kind(id) == kWild4;
}

/// "Letzte Karte" – shed all cards by matching colour or symbol.
///
/// Played through [apply] with plain events, so it can be sent over the
/// network and saved: `['deal', seed, stacking]`, `['play', card, colour]`
/// (colour only matters for wild cards), `['draw']`, `['keep']` (keep the
/// card just drawn) and `['last']` (call "Letzte Karte!" before playing the
/// second-to-last card).
class LastCardGame {
  LastCardGame({required this.players, this.first = 0});

  factory LastCardGame.replay(int players, List events, {int first = 0}) {
    final g = LastCardGame(players: players, first: first);
    for (final e in events) {
      g.apply(List.from(e as List));
    }
    return g;
  }

  static const handSize = 7;

  final int players;
  final int first;
  final List<List> events = [];

  int match = -1;
  int seed = 0;

  /// +2 and +4 can be stacked onto each other (secret rule of the host).
  bool stacking = false;

  List<List<int>> hands = [];
  List<int> pile = [];
  List<int> discard = [];
  int current = 0;
  int direction = 1;
  int color = 0;

  /// Cards the next player has to take (stacking only).
  int pendingDraw = 0;

  /// Card drawn this turn that may still be played.
  int? drawn;

  /// The player to move called "Letzte Karte!".
  bool called = false;

  /// Who got 2 penalty cards for forgetting the call last (for the UI).
  int? penalized;

  int _reshuffles = 0;
  int? winner;

  bool get dealt => match >= 0;
  bool get isOver => winner != null;
  int get top => discard.last;
  int? get toMove => !dealt || isOver ? null : current;

  int next([int steps = 1]) =>
      ((current + direction * steps) % players + players) % players;

  bool canPlay(int card) {
    if (!dealt || isOver || !hands[current].contains(card)) return false;
    if (drawn != null && card != drawn) return false;
    if (pendingDraw > 0) return LcCard.isDraw(card);
    if (LcCard.isWild(card)) return true;
    return LcCard.color(card) == color || LcCard.kind(card) == LcCard.kind(top);
  }

  List<int> playable() => [
    for (final c in hands[current])
      if (canPlay(c)) c,
  ];

  /// Calling makes sense with two cards, one of them playable.
  bool get canCall =>
      dealt &&
      !isOver &&
      !called &&
      hands[current].length == 2 &&
      playable().isNotEmpty;

  bool apply(List e) {
    switch (e) {
      case ['deal', final int s, final bool stack]:
        if (dealt && !isOver) return false;
        _deal(s, stack);
      case ['play', final int card, final int c]:
        if (!canPlay(card)) return false;
        if (LcCard.isWild(card) && (c < 0 || c > 3)) return false;
        _play(card, c);
      case ['draw']:
        if (!dealt || isOver || drawn != null) return false;
        if (pendingDraw > 0) {
          _take(current, pendingDraw);
          pendingDraw = 0;
          _advance(1);
        } else {
          final got = _take(current, 1);
          if (got.isNotEmpty && canPlay(got.single)) {
            drawn = got.single;
          } else {
            _advance(1);
          }
        }
      case ['keep']:
        if (drawn == null) return false;
        _advance(1);
      case ['last']:
        if (!canCall) return false;
        called = true;
      default:
        return false;
    }
    events.add(e);
    return true;
  }

  void _deal(int s, bool stack) {
    match++;
    seed = s;
    stacking = stack;
    pile = List.generate(LcCard.count, (i) => i)..shuffle(Random(s));
    hands = [for (var p = 0; p < players; p++) <int>[]];
    for (var i = 0; i < handSize; i++) {
      for (var p = 0; p < players; p++) {
        hands[p].add(pile.removeLast());
      }
    }
    // Start with a number card.
    final start = pile.lastWhere((c) => LcCard.kind(c) <= 9);
    pile.remove(start);
    discard = [start];
    color = LcCard.color(start);
    current = (first + match) % players;
    direction = 1;
    pendingDraw = 0;
    drawn = null;
    called = false;
    penalized = null;
    winner = null;
    _reshuffles = 0;
  }

  /// Takes up to [n] cards from the pile; returns them.
  List<int> _take(int player, int n) {
    final got = <int>[];
    for (var i = 0; i < n; i++) {
      if (pile.isEmpty) {
        if (discard.length <= 1) break;
        final t = discard.removeLast();
        pile = discard..shuffle(Random(seed * 7 + ++_reshuffles));
        discard = [t];
      }
      got.add(pile.removeLast());
    }
    hands[player].addAll(got);
    return got;
  }

  void _play(int card, int c) {
    final hand = hands[current];
    hand.remove(card);
    discard.add(card);
    color = LcCard.isWild(card) ? c : LcCard.color(card);
    drawn = null;
    if (hand.isEmpty) {
      winner = current;
      return;
    }
    penalized = null;
    if (hand.length == 1 && !called) {
      _take(current, 2);
      penalized = current;
    }
    switch (LcCard.kind(card)) {
      case kSkip:
        _advance(2);
      case kReverse:
        if (players == 2) {
          _advance(2);
        } else {
          direction = -direction;
          _advance(1);
        }
      case kDraw2 || kWild4:
        final n = LcCard.kind(card) == kDraw2 ? 2 : 4;
        if (stacking) {
          pendingDraw += n;
          _advance(1);
        } else {
          _take(next(), n);
          _advance(2);
        }
      default:
        _advance(1);
    }
  }

  void _advance(int steps) {
    current = next(steps);
    drawn = null;
    called = false;
  }
}

/// Computer player for "Letzte Karte".
class LastCardAi {
  LastCardAi([Random? random]) : _random = random ?? Random();
  final Random _random;

  List choose(LastCardGame g) {
    final options = g.playable();
    if (options.isEmpty) return g.drawn != null ? ['keep'] : ['draw'];
    // Mostly remembers to call (sometimes it forgets – that costs 2 cards).
    if (g.canCall && _random.nextDouble() < 0.9) return ['last'];
    final hand = g.hands[g.current];
    final nextCards = g.hands[g.next()].length;
    int score(int c) {
      final k = LcCard.kind(c);
      var s = k <= 9 ? k : 10;
      if (LcCard.isWild(c)) s -= 30; // keep for later
      if (k == kWild4 && nextCards <= 2) s += 60;
      if ((k == kDraw2 || k == kSkip) && nextCards <= 2) s += 40;
      // Stay in the colour we hold most of.
      if (!LcCard.isWild(c)) {
        s += hand.where((h) => LcCard.color(h) == LcCard.color(c)).length * 2;
      }
      return s;
    }

    final card = options.reduce((a, b) => score(a) >= score(b) ? a : b);
    return ['play', card, LcCard.isWild(card) ? _bestColor(hand, card) : -1];
  }

  static int _bestColor(List<int> hand, int except) {
    final counts = List.filled(4, 0);
    for (final c in hand) {
      if (c != except && !LcCard.isWild(c)) counts[LcCard.color(c)]++;
    }
    var best = 0;
    for (var i = 1; i < 4; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    return best;
  }
}
