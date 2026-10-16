import '../../core/proof.dart';
import 'yahtzee_logic.dart';

/// Dice of checked solo games (see [SeededRandom]).
typedef SeededDice = SeededRandom;

/// The record of a solo Würfelkönig game: the seed of the dice and every
/// move. It is published with the score so other devices can replay the
/// game and only show scores that were really played.
///
/// The seed starts with the player's public key, so nobody can publish a
/// good game of somebody else as their own.
class KniffelProof {
  KniffelProof(this.seed, [List<String>? moves, this.rules = 2])
    : moves = moves ?? [];

  /// A new game of the player with [pubkey].
  factory KniffelProof.start(String pubkey) =>
      KniffelProof(newProofSeed(pubkey));

  final String seed;

  /// Rules the game was played with: 1 = before the Kniffel bonus and
  /// joker rule, 2 = with them.
  final int rules;

  /// `r<mask>` for a roll (bit i set = die i held), or a category name.
  final List<String> moves;

  KniffelGame newGame() =>
      KniffelGame(1, random: SeededDice(seed), extraRules: rules >= 2);

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

  Map<String, dynamic> toJson() => {
    's': seed,
    'm': moves,
    if (rules != 1) 'v': rules,
  };

  static KniffelProof? fromJson(Object? j) {
    final p = readProof(j, maxMoves: 200);
    if (p == null) return null;
    final v = (j as Map)['v'] ?? 1;
    if (v != 1 && v != 2) return null;
    return KniffelProof(p.$1, p.$2, v as int);
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
    if (!seedOwnedBy(seed, author)) return null;
    final g = replay();
    if (g == null || !g.isOver) return null;
    return g.sheets[0].total;
  }
}
