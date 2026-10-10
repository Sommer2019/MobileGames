import 'dart:math';

/// The 60 cards: four colours with 1–13, four wizards and four fools.
class PCard {
  PCard._();

  static const count = 60;
  static const colors = 4;

  static bool isWizard(int id) => id >= 52 && id < 56;
  static bool isFool(int id) => id >= 56;
  static bool isSpecial(int id) => id >= 52;

  /// Colour 0–3, or −1 for wizards and fools.
  static int color(int id) => id < 52 ? id ~/ 13 : -1;

  /// 1–13 for colour cards.
  static int value(int id) => id < 52 ? id % 13 + 1 : 0;
}

enum ProphetPhase { waiting, trumpChoice, bidding, playing, roundOver, over }

/// "Stichprophet" – every round each player predicts how many tricks they
/// will take; only exact predictions score.
///
/// Rules: round n deals n cards to everybody. The next card of the pile
/// shows trump (a fool: no trump, a wizard: the dealer picks; the last
/// round has none). Colour must be followed; wizards and fools may always
/// be played. The first wizard wins the trick, then the highest trump,
/// then the highest card of the colour led; only fools: the first one.
/// Exact: 20 + 10 per trick, otherwise −10 per trick off.
///
/// Played through [apply] with plain events so it can be sent and saved:
/// `['deal', seed]`, `['trump', colour]`, `['bid', n]`, `['play', card]`.
class ProphetGame {
  ProphetGame({required this.players, this.first = 0, int? rounds})
    : rounds = rounds ?? PCard.count ~/ players,
      scores = List.filled(players, 0);

  factory ProphetGame.replay(
    int players,
    List events, {
    int first = 0,
    int? rounds,
  }) {
    final g = ProphetGame(players: players, first: first, rounds: rounds);
    for (final e in events) {
      g.apply(List.from(e as List));
    }
    return g;
  }

  final int players;

  /// Who deals the first round (rotates with every game).
  final int first;

  /// Number of rounds; round n has n cards.
  final int rounds;
  final List<List> events = [];

  /// Index of the current round (0 = one card each), −1 before the first.
  int round = -1;
  ProphetPhase phase = ProphetPhase.waiting;

  List<List<int>> hands = [];

  /// The card that shows trump (null: none turned up).
  int? trumpCard;

  /// Trump colour, or −1 for none.
  int trump = -1;

  List<int?> bids = [];
  List<int> won = [];

  /// The trick on the table as (seat, card); a full trick stays until the
  /// next card is played, so everybody can see it.
  List<(int, int)> trick = [];
  int current = 0;

  /// Who took the last full trick.
  int? lastWinner;

  final List<int> scores;

  /// Score change of every player per finished round.
  final List<List<int>> history = [];

  int get cardsThisRound => round + 1;
  int get dealer => (first + round) % players;
  bool get dealt => round >= 0;
  bool get isOver => phase == ProphetPhase.over;
  bool get isLastRound => round == rounds - 1;

  /// The seat that has to act, or null (waiting for the deal).
  int? get toMove => switch (phase) {
    ProphetPhase.trumpChoice ||
    ProphetPhase.bidding ||
    ProphetPhase.playing => current,
    _ => null,
  };

  int next(int seat) => (seat + 1) % players;

  bool get _trickFull => trick.length == players;

  /// The cards of the running trick (empty after a full one).
  List<(int, int)> get openTrick => _trickFull ? const [] : trick;

  /// The colour that must be followed in [cards], or null (nothing led
  /// yet, only fools so far, or a wizard led).
  static int? leadColor(List<(int, int)> cards) {
    for (final (_, c) in cards) {
      if (PCard.isFool(c)) continue;
      if (PCard.isWizard(c)) return null;
      return PCard.color(c);
    }
    return null;
  }

  /// The seat that takes [cards] with [trump].
  static int trickWinner(List<(int, int)> cards, int trump) {
    for (final (s, c) in cards) {
      if (PCard.isWizard(c)) return s;
    }
    final lead = leadColor(cards);
    (int, int)? best;
    int rank(int c) {
      if (PCard.isFool(c)) return 0;
      final col = PCard.color(c);
      if (col == trump) return 200 + PCard.value(c);
      if (col == lead) return 100 + PCard.value(c);
      return 1;
    }

    for (final e in cards) {
      if (best == null || rank(e.$2) > rank(best.$2)) best = e;
    }
    // Only fools (rank 0 everywhere): the first one.
    return best!.$1;
  }

  bool canPlay(int card) {
    if (phase != ProphetPhase.playing) return false;
    final hand = hands[current];
    if (!hand.contains(card)) return false;
    // Wizards and fools may always be played.
    if (PCard.isSpecial(card)) return true;
    final lead = leadColor(openTrick);
    if (lead == null || PCard.color(card) == lead) return true;
    return !hand.any((c) => PCard.color(c) == lead);
  }

  List<int> playable() => [
    for (final c in hands[current])
      if (canPlay(c)) c,
  ];

  /// Which predictions are allowed (any number from 0 to the cards).
  bool canBid(int n) =>
      phase == ProphetPhase.bidding && n >= 0 && n <= cardsThisRound;

  bool apply(List e) {
    switch (e) {
      case ['deal', final int seed]:
        if (phase != ProphetPhase.waiting && phase != ProphetPhase.roundOver) {
          return false;
        }
        _deal(seed);
      case ['trump', final int c]:
        if (phase != ProphetPhase.trumpChoice || c < 0 || c > 3) return false;
        trump = c;
        _startBidding();
      case ['bid', final int n]:
        if (!canBid(n)) return false;
        bids[current] = n;
        current = next(current);
        if (bids.every((b) => b != null)) {
          phase = ProphetPhase.playing;
          current = next(dealer);
        }
      case ['play', final int card]:
        if (!canPlay(card)) return false;
        _play(card);
      default:
        return false;
    }
    events.add(e);
    return true;
  }

  void _deal(int seed) {
    round++;
    final pile = List.generate(PCard.count, (i) => i)..shuffle(Random(seed));
    hands = [for (var p = 0; p < players; p++) <int>[]];
    for (var i = 0; i < cardsThisRound; i++) {
      for (var k = 1; k <= players; k++) {
        hands[(dealer + k) % players].add(pile.removeLast());
      }
    }
    trumpCard = pile.isEmpty ? null : pile.last;
    bids = List.filled(players, null);
    won = List.filled(players, 0);
    trick = [];
    lastWinner = null;
    final t = trumpCard;
    if (t != null && PCard.isWizard(t)) {
      trump = -1;
      phase = ProphetPhase.trumpChoice;
      current = dealer;
      return;
    }
    trump = t == null || PCard.isFool(t) ? -1 : PCard.color(t);
    _startBidding();
  }

  void _startBidding() {
    phase = ProphetPhase.bidding;
    current = next(dealer);
  }

  void _play(int card) {
    if (_trickFull) trick = [];
    hands[current].remove(card);
    trick = [...trick, (current, card)];
    if (!_trickFull) {
      current = next(current);
      return;
    }
    final w = trickWinner(trick, trump);
    won[w]++;
    lastWinner = w;
    current = w;
    if (hands.every((h) => h.isEmpty)) _endRound();
  }

  void _endRound() {
    final delta = [
      for (var p = 0; p < players; p++)
        bids[p] == won[p] ? 20 + 10 * won[p] : -10 * (bids[p]! - won[p]).abs(),
    ];
    for (var p = 0; p < players; p++) {
      scores[p] += delta[p];
    }
    history.add(delta);
    phase = isLastRound ? ProphetPhase.over : ProphetPhase.roundOver;
  }

  /// Who predicted exactly in the last finished round.
  List<int> get exact => [
    for (var p = 0; p < players; p++)
      if (history.isNotEmpty && history.last[p] > 0) p,
  ];

  List<int> winners() {
    final best = scores.reduce(max);
    return [
      for (var p = 0; p < players; p++)
        if (scores[p] == best) p,
    ];
  }
}

/// Computer player: predicts from the strength of its hand and then tries
/// to take exactly that many tricks.
class ProphetAi {
  ProphetAi([Random? random]) : _random = random ?? Random();
  final Random _random;

  List choose(ProphetGame g) => switch (g.phase) {
    ProphetPhase.trumpChoice => ['trump', _bestColor(g.hands[g.current])],
    ProphetPhase.bidding => ['bid', bid(g)],
    _ => ['play', _card(g)],
  };

  /// How strong [card] is for taking tricks (relative; see [bid]).
  double _strength(ProphetGame g, int card) {
    if (PCard.isWizard(card)) return 1;
    if (PCard.isFool(card)) return 0;
    final v = PCard.value(card);
    if (PCard.color(card) == g.trump) return 0.45 + 0.04 * v;
    return v >= 11 ? 0.12 + 0.06 * (v - 10) : 0.01 * v;
  }

  int bid(ProphetGame g) {
    final hand = g.hands[g.current];
    final mine = hand.fold(0.0, (a, c) => a + _strength(g, c));
    // The average hand: this share of all tricks is expected.
    var all = 0.0;
    for (var c = 0; c < PCard.count; c++) {
      all += _strength(g, c);
    }
    final average = all / PCard.count * hand.length;
    // Small hands: a strong card is more often a sure trick.
    final share = average == 0 ? 0.0 : mine / average / g.players;
    final expected = g.cardsThisRound <= 2
        ? hand.fold(0.0, (a, c) => a + _single(g, c))
        : share * g.cardsThisRound;
    // A little noise so the computer is not fully predictable.
    final n = (expected + (_random.nextDouble() - 0.5) * 0.3).round();
    return n.clamp(0, g.cardsThisRound);
  }

  /// Chance of [card] to take a trick when only one or two are played.
  double _single(ProphetGame g, int card) {
    if (PCard.isWizard(card)) return 0.95;
    if (PCard.isFool(card)) return 0;
    final v = PCard.value(card);
    final crowd = 3 / g.players;
    if (PCard.color(card) == g.trump) {
      return (v >= 11 ? 0.85 : (v >= 7 ? 0.5 : 0.3)) * (0.6 + 0.4 * crowd);
    }
    return (v == 13 ? 0.6 : (v == 12 ? 0.35 : (v == 11 ? 0.2 : 0.03))) * crowd;
  }

  static int _bestColor(List<int> hand) {
    final strength = List.filled(4, 0);
    for (final c in hand) {
      if (!PCard.isSpecial(c)) strength[PCard.color(c)] += 5 + PCard.value(c);
    }
    var best = 0;
    for (var i = 1; i < 4; i++) {
      if (strength[i] > strength[best]) best = i;
    }
    return best;
  }

  /// A value to compare cards by: higher takes tricks more easily.
  static int _power(ProphetGame g, int c) {
    if (PCard.isWizard(c)) return 100;
    if (PCard.isFool(c)) return -1;
    return (PCard.color(c) == g.trump ? 50 : 0) + PCard.value(c);
  }

  int _card(ProphetGame g) {
    final me = g.current;
    final options = g.playable();
    final need = g.bids[me]! - g.won[me];
    final open = g.openTrick;
    bool wins(int c) =>
        ProphetGame.trickWinner([...open, (me, c)], g.trump) == me;
    final byPower = List.of(options)
      ..sort((a, b) => _power(g, a).compareTo(_power(g, b)));
    final last = open.length == g.players - 1;
    if (need > 0) {
      final winning = byPower.where(wins).toList();
      if (winning.isNotEmpty) {
        if (last) return winning.first; // the cheapest win
        // Others still play: the weakest card that is fairly safe; a
        // wizard only when nothing else will do.
        final tricksLeft = g.hands[me].length;
        if (need >= tricksLeft) return winning.last;
        final safe = winning.where((c) => _power(g, c) >= 12).toList();
        return safe.isNotEmpty ? safe.first : winning.last;
      }
      // Cannot win this one: get rid of the weakest card.
      return byPower.first;
    }
    // Enough tricks: the strongest card that still loses.
    final losing = byPower.where((c) => !wins(c)).toList();
    if (losing.isNotEmpty) return losing.last;
    return byPower.first;
  }
}
