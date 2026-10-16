import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'yahtzee_logic.dart';

/// Dice that follow from a seed: SHA-256 of "seed:counter", the same on
/// every device. A solo game rolled with them can be replayed by anybody.
class SeededDice implements Random {
  SeededDice(this.seed);

  final String seed;
  int _counter = 0;
  List<int> _bytes = const [];
  int _pos = 0;

  int _byte() {
    if (_pos >= _bytes.length) {
      _bytes = sha256.convert(utf8.encode('$seed:${_counter++}')).bytes;
      _pos = 0;
    }
    return _bytes[_pos++];
  }

  @override
  int nextInt(int max) {
    if (max <= 0 || max > 256) throw RangeError.range(max, 1, 256);
    // Rejection sampling keeps every value equally likely.
    final limit = 256 - 256 % max;
    while (true) {
      final b = _byte();
      if (b < limit) return b % max;
    }
  }

  @override
  bool nextBool() => _byte() & 1 == 1;

  @override
  double nextDouble() =>
      ((_byte() << 24) | (_byte() << 16) | (_byte() << 8) | _byte()) /
      4294967296.0;
}

/// The record of a solo Würfelkönig game: the seed of the dice and every
/// move. It is published with the score so other devices can replay the
/// game and only show scores that were really played.
///
/// The seed starts with the player's public key, so nobody can publish a
/// good game of somebody else as their own.
class KniffelProof {
  KniffelProof(this.seed, [List<String>? moves]) : moves = moves ?? [];

  /// A new game of the player with [pubkey].
  factory KniffelProof.start(String pubkey) =>
      KniffelProof('$pubkey:${DateTime.now().microsecondsSinceEpoch}');

  final String seed;

  /// `r<mask>` for a roll (bit i set = die i held), or a category name.
  final List<String> moves;

  KniffelGame newGame() => KniffelGame(1, random: SeededDice(seed));

  /// Notes a roll; call before rolling [game].
  void roll(KniffelGame game) {
    var mask = 0;
    if (game.hasRolled) {
      for (var i = 0; i < 5; i++) {
        if (game.held[i]) mask |= 1 << i;
      }
    }
    moves.add('r$mask');
  }

  void score(KniffelCategory c) => moves.add(c.name);

  Map<String, dynamic> toJson() => {'s': seed, 'm': moves};

  static KniffelProof? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['s'], m = j['m'];
    if (s is! String || m is! List || m.length > 200) return null;
    if (m.any((e) => e is! String)) return null;
    return KniffelProof(s, m.cast<String>().toList());
  }

  /// Plays the moves again; null if any move is impossible.
  KniffelGame? replay() {
    final g = newGame();
    for (final mv in moves) {
      if (mv.startsWith('r')) {
        final mask = int.tryParse(mv.substring(1));
        if (mask == null || mask < 0 || mask > 31 || !g.canRoll) return null;
        if (g.hasRolled) {
          g.held = [for (var i = 0; i < 5; i++) mask & (1 << i) != 0];
        } else if (mask != 0) {
          return null;
        }
        g.roll();
      } else {
        final c = KniffelCategory.values.where((c) => c.name == mv);
        if (c.isEmpty || !g.score(c.single)) return null;
      }
    }
    return g;
  }

  /// The score of the finished game if it belongs to [author], else null.
  int? verify(String author) {
    if (!seed.startsWith('$author:')) return null;
    final g = replay();
    if (g == null || !g.isOver) return null;
    return g.sheets[0].total;
  }
}
