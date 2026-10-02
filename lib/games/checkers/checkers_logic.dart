import 'dart:math';

/// Dame (German draughts) on an 8×8 board.
///
/// Rules: men move one square diagonally forward and capture forward and
/// backward; capturing is mandatory and multi-captures must be completed;
/// kings are "flying" (move and capture over any distance). A man that
/// ends its move on the far row becomes a king. Whoever cannot move loses.
enum Side { white, black }

class Piece {
  const Piece(this.side, {this.king = false});
  final Side side;
  final bool king;
}

class CheckersMove {
  const CheckersMove(this.path, this.captured);

  /// Squares visited (start, landing squares...).
  final List<(int, int)> path;
  final List<(int, int)> captured;

  (int, int) get from => path.first;
  (int, int) get to => path.last;
  bool get isCapture => captured.isNotEmpty;

  List<List<int>> toJson() => [
    for (final (r, c) in path) [r, c],
  ];

  static List<(int, int)> pathFromJson(List<dynamic> j) => [
    for (final p in j) ((p as List)[0] as int, p[1] as int),
  ];
}

class CheckersGame {
  CheckersGame() {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if ((r + c).isOdd) {
          if (r < 3) board[r][c] = const Piece(Side.black);
          if (r > 4) board[r][c] = const Piece(Side.white);
        }
      }
    }
  }

  /// board[row][col]; row 0 is black's home row (top).
  final List<List<Piece?>> board = List.generate(
    8,
    (_) => List.filled(8, null),
  );
  Side turn = Side.white;
  Side? winner;
  bool draw = false;
  int quietMoves = 0; // king moves without capture
  CheckersMove? lastMove;

  bool get isOver => winner != null || draw;

  static bool inside(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  int count(Side s) =>
      board.expand((row) => row).where((p) => p?.side == s).length;

  /// All legal moves for the side to move. If any capture exists, only
  /// captures are legal.
  List<CheckersMove> legalMoves() {
    if (isOver) return const [];
    final captures = <CheckersMove>[];
    final quiet = <CheckersMove>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p == null || p.side != turn) continue;
        _captures(r, c, p, [(r, c)], [], captures);
        if (captures.isEmpty) _quietMoves(r, c, p, quiet);
      }
    }
    return captures.isNotEmpty ? captures : quiet;
  }

  int _forward(Side s) => s == Side.white ? -1 : 1;

  void _quietMoves(int r, int c, Piece p, List<CheckersMove> out) {
    for (final (dr, dc) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      if (!p.king && dr != _forward(p.side)) continue;
      var nr = r + dr, nc = c + dc;
      while (inside(nr, nc) && board[nr][nc] == null) {
        out.add(CheckersMove([(r, c), (nr, nc)], const []));
        if (!p.king) break;
        nr += dr;
        nc += dc;
      }
    }
  }

  void _captures(
    int r,
    int c,
    Piece p,
    List<(int, int)> path,
    List<(int, int)> taken,
    List<CheckersMove> out,
  ) {
    final start = path.first;
    bool empty(int rr, int cc) => board[rr][cc] == null || (rr, cc) == start;
    for (final (dr, dc) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      var nr = r + dr, nc = c + dc;
      if (p.king) {
        while (inside(nr, nc) && empty(nr, nc)) {
          nr += dr;
          nc += dc;
        }
      }
      if (!inside(nr, nc)) continue;
      final victim = board[nr][nc];
      if (victim == null || victim.side == p.side || taken.contains((nr, nc))) {
        continue;
      }
      var lr = nr + dr, lc = nc + dc;
      while (inside(lr, lc) && empty(lr, lc)) {
        final newPath = [...path, (lr, lc)];
        final newTaken = [...taken, (nr, nc)];
        final promotes = !p.king && lr == (p.side == Side.white ? 0 : 7);
        if (promotes) {
          // Reaching the far row ends the move.
          out.add(CheckersMove(newPath, newTaken));
        } else {
          final before = out.length;
          _captures(lr, lc, p, newPath, newTaken, out);
          if (out.length == before) out.add(CheckersMove(newPath, newTaken));
        }
        if (!p.king) break;
        lr += dr;
        lc += dc;
      }
    }
  }

  /// Plays a legal move given by its path. Returns false if illegal.
  bool playPath(List<(int, int)> path) {
    for (final m in legalMoves()) {
      if (_samePath(m.path, path)) {
        _apply(m);
        return true;
      }
    }
    return false;
  }

  static bool _samePath(List<(int, int)> a, List<(int, int)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _apply(CheckersMove m) {
    final (fr, fc) = m.from;
    final (tr, tc) = m.to;
    var p = board[fr][fc]!;
    final movedKing = p.king;
    board[fr][fc] = null;
    for (final (cr, cc) in m.captured) {
      board[cr][cc] = null;
    }
    if (!p.king && tr == (p.side == Side.white ? 0 : 7)) {
      p = Piece(p.side, king: true);
    }
    board[tr][tc] = p;
    quietMoves = (m.isCapture || !movedKing) ? 0 : quietMoves + 1;
    lastMove = m;
    turn = turn == Side.white ? Side.black : Side.white;
    if (legalMoves().isEmpty) {
      winner = turn == Side.white ? Side.black : Side.white;
    } else if (quietMoves >= 50) {
      draw = true;
    }
  }

  CheckersGame copy() {
    final g = CheckersGame();
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        g.board[r][c] = board[r][c];
      }
    }
    g
      ..turn = turn
      ..winner = winner
      ..draw = draw
      ..quietMoves = quietMoves;
    return g;
  }

  /// Simple computer player: prefers big captures and avoids giving the
  /// opponent captures (one move lookahead).
  CheckersMove? aiMove([Random? random]) {
    final r = random ?? Random();
    final moves = legalMoves();
    if (moves.isEmpty) return null;
    double best = -1e9;
    final bestMoves = <CheckersMove>[];
    for (final m in moves) {
      final g = copy().._apply(m);
      var score = m.captured.length * 10.0;
      if (g.winner == turn) score += 1000;
      final replies = g.legalMoves();
      final threat = replies.fold(0, (a, x) => max(a, x.captured.length));
      score -= threat * 9.0;
      final (tr, _) = m.to;
      // Advance men, promotions are valuable.
      if (!(board[m.from.$1][m.from.$2]?.king ?? false)) {
        score += (turn == Side.white ? 7 - tr : tr) * 0.3;
        if (g.board[m.to.$1][m.to.$2]?.king ?? false) score += 8;
      }
      score += r.nextDouble();
      if (score > best) {
        best = score;
        bestMoves
          ..clear()
          ..add(m);
      }
    }
    return bestMoves.first;
  }
}
