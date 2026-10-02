import 'dart:math';

import 'package:chess/chess.dart' as ch;

enum ChessSide { white, black }

/// Thin wrapper around the `chess` package (full rules incl. castling,
/// en passant, promotion, draw detection).
class ChessGame {
  ChessGame() : _c = ch.Chess();

  final ch.Chess _c;

  static const files = 'abcdefgh';

  static String square(int file, int rank) => '${files[file]}${rank + 1}';

  ChessSide get turn =>
      _c.turn == ch.Color.WHITE ? ChessSide.white : ChessSide.black;

  /// Piece letter (uppercase = white, lowercase = black) or null.
  String? pieceAt(String square) {
    final p = _c.get(square);
    if (p == null) return null;
    final letter = p.type.name;
    return p.color == ch.Color.WHITE ? letter.toUpperCase() : letter;
  }

  ChessSide? colorAt(String square) {
    final p = _c.get(square);
    if (p == null) return null;
    return p.color == ch.Color.WHITE ? ChessSide.white : ChessSide.black;
  }

  /// Legal target squares for the piece on [from].
  List<String> targets(String from) => {
    for (final m in _c.moves(<String, dynamic>{
      'square': from,
      'verbose': true,
    }))
      (m as Map)['to'] as String,
  }.toList();

  bool isPromotion(String from, String to) {
    final p = _c.get(from);
    if (p == null || p.type != ch.Chess.PAWN) return false;
    return to.endsWith('8') || to.endsWith('1');
  }

  /// Makes a move. [promotion] is one of q, r, b, n.
  bool move(String from, String to, {String? promotion}) {
    final m = <String, String>{'from': from, 'to': to};
    if (isPromotion(from, to)) m['promotion'] = promotion ?? 'q';
    final ok = _c.move(m);
    if (ok) lastMove = (from, to);
    return ok;
  }

  (String, String)? lastMove;

  bool get inCheck => _c.in_check;
  bool get isCheckmate => _c.in_checkmate;
  bool get isStalemate => _c.in_stalemate;
  bool get isDraw => _c.in_draw;
  bool get isOver => _c.game_over;

  String get fen => _c.fen;
  List<String?> get history => _c.san_moves();

  String statusText() {
    if (isCheckmate) {
      return turn == ChessSide.white
          ? 'Schachmatt – Schwarz gewinnt'
          : 'Schachmatt – Weiß gewinnt';
    }
    if (isStalemate) return 'Patt – Remis';
    if (isDraw) return 'Remis';
    final side = turn == ChessSide.white ? 'Weiß' : 'Schwarz';
    return inCheck ? '$side steht im Schach' : '$side ist am Zug';
  }

  /// A simple computer opponent: two ply material search with randomness.
  /// [strong] (secret "grandmaster") uses a positional evaluation and plays
  /// almost without randomness.
  (String, String, String?)? aiMove([Random? random, bool strong = false]) {
    final r = random ?? Random();
    final moves = _c.moves({'verbose': true}).cast<Map>();
    if (moves.isEmpty) return null;
    final me = _c.turn;
    double best = -1e9;
    final bestMoves = <Map>[];
    for (final m in moves) {
      final copy = ch.Chess.fromFEN(_c.fen);
      copy.move({
        'from': m['from'],
        'to': m['to'],
        'promotion': m['promotion'] ?? 'q',
      });
      double score;
      if (copy.in_checkmate) {
        score = 1e6;
      } else if (copy.in_draw) {
        score = 0;
      } else {
        // Assume the opponent replies with its best capture.
        var worst = 1e9;
        for (final reply in copy.moves({'verbose': true}).cast<Map>()) {
          final c2 = ch.Chess.fromFEN(copy.fen);
          c2.move({
            'from': reply['from'],
            'to': reply['to'],
            'promotion': reply['promotion'] ?? 'q',
          });
          final s = c2.in_checkmate
              ? -1e6
              : (strong ? _position(c2, me) : _material(c2, me));
          if (s < worst) worst = s;
        }
        score = worst == 1e9
            ? (strong ? _position(copy, me) : _material(copy, me))
            : worst;
      }
      score += r.nextDouble() * (strong ? 0.02 : 0.3);
      if (score > best + 1e-9) {
        best = score;
        bestMoves
          ..clear()
          ..add(m);
      } else if ((score - best).abs() < 1e-9) {
        bestMoves.add(m);
      }
    }
    final m = bestMoves[r.nextInt(bestMoves.length)];
    return (m['from'] as String, m['to'] as String, m['promotion'] as String?);
  }

  static const _values = {
    'p': 1.0,
    'n': 3.0,
    'b': 3.2,
    'r': 5.0,
    'q': 9.0,
    'k': 0.0,
  };

  /// Material plus position: development, advanced pawns, centre control,
  /// a sheltered king.
  double _position(ch.Chess c, ch.Color me) {
    var score = 0.0;
    for (var f = 0; f < 8; f++) {
      for (var rk = 0; rk < 8; rk++) {
        final p = c.get(square(f, rk));
        if (p == null) continue;
        final white = p.color == ch.Color.WHITE;
        // Rank from the owner's point of view, 0 = home rank.
        final own = white ? rk : 7 - rk;
        final centre = 3.5 - max((f - 3.5).abs(), (rk - 3.5).abs());
        var v = _values[p.type.name]!;
        switch (p.type.name) {
          case 'p':
            v += own * 0.05 + (f >= 3 && f <= 4 ? 0.1 : 0);
          case 'n':
          case 'b':
            v += centre * 0.08 + (own == 0 ? -0.25 : 0);
          case 'q':
            v += centre * 0.03;
          case 'k':
            // Stay home and tucked to the side until the endgame.
            v += (own == 0 ? 0.2 : -0.1 * own) + (f <= 2 || f >= 6 ? 0.2 : 0);
          default:
            v += centre * 0.02;
        }
        score += p.color == me ? v : -v;
      }
    }
    if (c.in_check) score += c.turn == me ? -0.3 : 0.3;
    return score;
  }

  double _material(ch.Chess c, ch.Color me) {
    var score = 0.0;
    for (var f = 0; f < 8; f++) {
      for (var rk = 0; rk < 8; rk++) {
        final p = c.get(square(f, rk));
        if (p == null) continue;
        var v = _values[p.type.name]!;
        // Small bonus for central pieces.
        if (f >= 2 && f <= 5 && rk >= 2 && rk <= 5) v += 0.1;
        score += p.color == me ? v : -v;
      }
    }
    return score;
  }
}
