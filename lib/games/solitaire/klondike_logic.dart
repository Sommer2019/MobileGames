import 'dart:math';

class PlayingCard {
  PlayingCard(this.suit, this.rank, {this.faceUp = false});

  /// 0 = ♠, 1 = ♥, 2 = ♦, 3 = ♣
  final int suit;

  /// 1 = Ass … 11 = Bube, 12 = Dame, 13 = König
  final int rank;
  bool faceUp;

  bool get red => suit == 1 || suit == 2;

  String get suitSymbol => const ['♠', '♥', '♦', '♣'][suit];
  String get rankLabel => switch (rank) {
    1 => 'A',
    11 => 'B',
    12 => 'D',
    13 => 'K',
    _ => '$rank',
  };

  PlayingCard copy() => PlayingCard(suit, rank, faceUp: faceUp);

  @override
  String toString() => '$rankLabel$suitSymbol${faceUp ? '' : '*'}';
}

enum PileKind { stock, waste, foundation, tableau }

/// A place cards can come from or go to.
class PileRef {
  const PileRef(this.kind, [this.index = 0]);
  final PileKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is PileRef && other.kind == kind && other.index == index;
  @override
  int get hashCode => Object.hash(kind, index);
}

/// Klondike solitaire (draw 1 or draw 3, unlimited passes through the stock).
///
/// Scoring follows the classic Windows rules: waste → tableau +5,
/// to a foundation +10, turning a tableau card +5, foundation → tableau −15,
/// recycling the waste −100 (draw 1) or −20 (draw 3). Never below 0.
/// A win adds a time bonus ([timeBonus]).
class KlondikeGame {
  KlondikeGame({this.drawCount = 1, Random? random}) {
    final deck = [
      for (var s = 0; s < 4; s++)
        for (var r = 1; r <= 13; r++) PlayingCard(s, r),
    ]..shuffle(random ?? Random());
    for (var i = 0; i < 7; i++) {
      for (var j = i; j < 7; j++) {
        tableau[j].add(deck.removeLast());
      }
      tableau[i].last.faceUp = true;
    }
    stock.addAll(deck);
  }

  /// A saved game (see [toJson]); the undo history is not kept.
  factory KlondikeGame.fromJson(Map<String, dynamic> j) {
    final g = KlondikeGame(drawCount: j['draw'] as int);
    List<PlayingCard> pile(Object? raw) => [
      for (final v in (raw as List).cast<int>())
        PlayingCard(v ~/ 100 % 10, v % 100, faceUp: v >= 1000),
    ];
    g.stock
      ..clear()
      ..addAll(pile(j['stock']));
    g.waste
      ..clear()
      ..addAll(pile(j['waste']));
    final f = j['foundations'] as List, t = j['tableau'] as List;
    for (var i = 0; i < 4; i++) {
      g.foundations[i]
        ..clear()
        ..addAll(pile(f[i]));
    }
    for (var i = 0; i < 7; i++) {
      g.tableau[i]
        ..clear()
        ..addAll(pile(t[i]));
    }
    g
      ..moves = j['moves'] as int
      ..score = j['score'] as int;
    final all = [g.stock, g.waste, ...g.foundations, ...g.tableau];
    if (all.fold(0, (n, p) => n + p.length) != 52) {
      throw const FormatException('cards missing');
    }
    return g;
  }

  Map<String, dynamic> toJson() {
    List<int> pile(List<PlayingCard> p) => [
      for (final c in p) (c.faceUp ? 1000 : 0) + c.suit * 100 + c.rank,
    ];
    return {
      'draw': drawCount,
      'stock': pile(stock),
      'waste': pile(waste),
      'foundations': [for (final p in foundations) pile(p)],
      'tableau': [for (final p in tableau) pile(p)],
      'moves': moves,
      'score': score,
    };
  }

  final int drawCount;
  final List<PlayingCard> stock = [];
  final List<PlayingCard> waste = [];
  final List<List<PlayingCard>> foundations = List.generate(4, (_) => []);
  final List<List<PlayingCard>> tableau = List.generate(7, (_) => []);
  final List<_Snapshot> _history = [];
  int moves = 0;
  int score = 0;

  void _addScore(int points) => score = max(0, score + points);

  /// Bonus for winning after [seconds] (as in Windows Solitaire).
  static int timeBonus(int seconds) => seconds < 30 ? 23333 : 700000 ~/ seconds;

  bool get won => foundations.every((f) => f.length == 13);
  bool get canUndo => _history.isNotEmpty;

  List<PlayingCard> pile(PileRef p) => switch (p.kind) {
    PileKind.stock => stock,
    PileKind.waste => waste,
    PileKind.foundation => foundations[p.index],
    PileKind.tableau => tableau[p.index],
  };

  // ------------------------------------------------------------- rules

  bool canStackOnTableau(PlayingCard card, int t) {
    final pile = tableau[t];
    if (pile.isEmpty) return card.rank == 13;
    final top = pile.last;
    return top.faceUp && top.red != card.red && top.rank == card.rank + 1;
  }

  bool canStackOnFoundation(PlayingCard card, int f) {
    final pile = foundations[f];
    if (pile.isEmpty) return card.rank == 1;
    return pile.last.suit == card.suit && pile.last.rank == card.rank - 1;
  }

  /// Cards that would move when picking up [from] at [index]
  /// (a face-up run on the tableau, otherwise only the top card).
  List<PlayingCard>? movable(PileRef from, int index) {
    final cards = pile(from);
    if (index < 0 || index >= cards.length) return null;
    switch (from.kind) {
      case PileKind.stock:
        return null;
      case PileKind.waste:
      case PileKind.foundation:
        return index == cards.length - 1 ? [cards.last] : null;
      case PileKind.tableau:
        if (!cards[index].faceUp) return null;
        return cards.sublist(index);
    }
  }

  bool canMove(PileRef from, int index, PileRef to) {
    if (from == to) return false;
    final run = movable(from, index);
    if (run == null) return false;
    switch (to.kind) {
      case PileKind.foundation:
        return run.length == 1 && canStackOnFoundation(run.first, to.index);
      case PileKind.tableau:
        return canStackOnTableau(run.first, to.index);
      case PileKind.stock:
      case PileKind.waste:
        return false;
    }
  }

  bool move(PileRef from, int index, PileRef to) {
    if (!canMove(from, index, to)) return false;
    _save();
    final src = pile(from);
    final run = src.sublist(index);
    src.removeRange(index, src.length);
    pile(to).addAll(run);
    if (to.kind == PileKind.foundation) {
      _addScore(10);
    } else if (from.kind == PileKind.waste) {
      _addScore(5);
    } else if (from.kind == PileKind.foundation) {
      _addScore(-15);
    }
    if (from.kind == PileKind.tableau && src.isNotEmpty && !src.last.faceUp) {
      src.last.faceUp = true;
      _addScore(5);
    }
    moves++;
    return true;
  }

  /// Draws from the stock, or turns the waste over when the stock is empty.
  bool draw() {
    if (stock.isEmpty && waste.isEmpty) return false;
    _save();
    if (stock.isEmpty) {
      stock.addAll(waste.reversed.map((c) => c..faceUp = false));
      waste.clear();
      _addScore(drawCount == 1 ? -100 : -20);
    } else {
      for (var i = 0; i < drawCount && stock.isNotEmpty; i++) {
        waste.add(stock.removeLast()..faceUp = true);
      }
    }
    moves++;
    return true;
  }

  /// Best target for a tap on a card: foundation for single cards, then a
  /// tableau pile (non-empty piles before empty ones).
  PileRef? bestTarget(PileRef from, int index) {
    final run = movable(from, index);
    if (run == null) return null;
    if (run.length == 1 && from.kind != PileKind.foundation) {
      for (var f = 0; f < 4; f++) {
        final to = PileRef(PileKind.foundation, f);
        if (canMove(from, index, to)) return to;
      }
    }
    PileRef? empty;
    for (var t = 0; t < 7; t++) {
      final to = PileRef(PileKind.tableau, t);
      if (!canMove(from, index, to)) continue;
      // Moving a king from one empty spot to another is pointless.
      if (tableau[t].isEmpty) {
        if (from.kind == PileKind.tableau && index == 0) continue;
        empty ??= to;
        continue;
      }
      return to;
    }
    return empty;
  }

  /// True when all cards are face up and the stock is used up – the rest
  /// can be played automatically.
  bool get canAutoComplete =>
      !won &&
      stock.isEmpty &&
      waste.isEmpty &&
      tableau.every((p) => p.every((c) => c.faceUp));

  /// Plays one card to a foundation. Returns false when nothing fits.
  bool autoStep() {
    for (var t = 0; t < 7; t++) {
      final p = tableau[t];
      if (p.isEmpty) continue;
      final from = PileRef(PileKind.tableau, t);
      for (var f = 0; f < 4; f++) {
        if (move(from, p.length - 1, PileRef(PileKind.foundation, f))) {
          return true;
        }
      }
    }
    if (waste.isNotEmpty) {
      for (var f = 0; f < 4; f++) {
        if (move(
          const PileRef(PileKind.waste),
          waste.length - 1,
          PileRef(PileKind.foundation, f),
        )) {
          return true;
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- undo

  void _save() {
    _history.add(_Snapshot(this));
    if (_history.length > 200) _history.removeAt(0);
  }

  bool undo() {
    if (_history.isEmpty) return false;
    _history.removeLast().restore(this);
    return true;
  }
}

class _Snapshot {
  _Snapshot(KlondikeGame g)
    : stock = [for (final c in g.stock) c.copy()],
      waste = [for (final c in g.waste) c.copy()],
      foundations = [
        for (final p in g.foundations) [for (final c in p) c.copy()],
      ],
      tableau = [
        for (final p in g.tableau) [for (final c in p) c.copy()],
      ],
      moves = g.moves,
      score = g.score;

  final List<PlayingCard> stock, waste;
  final List<List<PlayingCard>> foundations, tableau;
  final int moves, score;

  void restore(KlondikeGame g) {
    g.stock
      ..clear()
      ..addAll(stock);
    g.waste
      ..clear()
      ..addAll(waste);
    for (var i = 0; i < 4; i++) {
      g.foundations[i]
        ..clear()
        ..addAll(foundations[i]);
    }
    for (var i = 0; i < 7; i++) {
      g.tableau[i]
        ..clear()
        ..addAll(tableau[i]);
    }
    g.moves = moves;
    g.score = score;
  }
}
