/// Pure game logic for "4 gewinnt" (Connect Four) for 2–4 players.
/// With more players the board grows so there is enough room.
class ConnectFourGame {
  ConnectFourGame({this.players = 2})
    : assert(players >= 2 && players <= 4),
      columns = const [7, 7, 9, 10][players - 1],
      rows = const [6, 6, 7, 8][players - 1] {
    board = List.generate(rows, (_) => List.filled(columns, 0));
  }

  /// Replays saved [moves].
  factory ConnectFourGame.replay(int players, List<dynamic> moves) {
    final g = ConnectFourGame(players: players);
    for (final c in moves) {
      if (g.drop(c as int) < 0) throw FormatException('illegal move $c');
    }
    return g;
  }

  final int players;

  /// Columns played so far (for saving the game).
  final List<int> moves = [];
  final int columns;
  final int rows;

  /// board[row][col], row 0 is the top. 0 = empty, otherwise player 1..4.
  late final List<List<int>> board;

  int currentPlayer = 1;
  int winner = 0;
  bool draw = false;
  List<(int, int)> winningCells = const [];

  bool get isOver => winner != 0 || draw;

  bool canDrop(int col) =>
      !isOver && col >= 0 && col < columns && board[0][col] == 0;

  /// Drops a disc for the current player. Returns the row it landed in,
  /// or -1 if the move is illegal.
  int drop(int col) {
    if (!canDrop(col)) return -1;
    var row = rows - 1;
    while (board[row][col] != 0) {
      row--;
    }
    board[row][col] = currentPlayer;
    moves.add(col);
    final line = _findLine(row, col);
    if (line != null) {
      winner = currentPlayer;
      winningCells = line;
    } else if (board[0].every((c) => c != 0)) {
      draw = true;
    } else {
      currentPlayer = currentPlayer % players + 1;
    }
    return row;
  }

  List<(int, int)>? _findLine(int row, int col) {
    final p = board[row][col];
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final (dr, dc) in dirs) {
      final cells = <(int, int)>[(row, col)];
      for (final sign in [1, -1]) {
        var r = row + dr * sign, c = col + dc * sign;
        while (r >= 0 &&
            r < rows &&
            c >= 0 &&
            c < columns &&
            board[r][c] == p) {
          cells.add((r, c));
          r += dr * sign;
          c += dc * sign;
        }
      }
      if (cells.length >= 4) return cells;
    }
    return null;
  }

  ConnectFourGame copy() {
    final g = ConnectFourGame(players: players);
    for (var r = 0; r < rows; r++) {
      g.board[r].setAll(0, board[r]);
    }
    g.currentPlayer = currentPlayer;
    g.winner = winner;
    g.draw = draw;
    return g;
  }
}

/// Columns ordered from the center outwards (better pruning).
List<int> _order(ConnectFourGame g) {
  final center = g.columns ~/ 2;
  return [for (var c = 0; c < g.columns; c++) c]
    ..sort((a, b) => (a - center).abs().compareTo((b - center).abs()));
}

/// Simple minimax AI for single-device play against the computer.
class ConnectFourAi {
  ConnectFourAi({this.depth = 5});
  final int depth;

  int bestMove(ConnectFourGame game) {
    final me = game.currentPlayer;
    var bestScore = -1 << 30;
    var best = -1;
    for (final col in _order(game)) {
      if (!game.canDrop(col)) continue;
      final g = game.copy()..drop(col);
      final score = _minimax(g, depth - 1, -1 << 30, 1 << 30, me);
      if (score > bestScore) {
        bestScore = score;
        best = col;
      }
    }
    return best;
  }

  int _minimax(ConnectFourGame g, int depth, int alpha, int beta, int me) {
    if (g.winner != 0) return g.winner == me ? 100000 + depth : -100000 - depth;
    if (g.draw) return 0;
    if (depth == 0) return _evaluate(g, me);
    final maximizing = g.currentPlayer == me;
    var value = maximizing ? -1 << 30 : 1 << 30;
    for (final col in _order(g)) {
      if (!g.canDrop(col)) continue;
      final child = g.copy()..drop(col);
      final score = _minimax(child, depth - 1, alpha, beta, me);
      if (maximizing) {
        if (score > value) value = score;
        if (value > alpha) alpha = value;
      } else {
        if (score < value) value = score;
        if (value < beta) beta = value;
      }
      if (alpha >= beta) break;
    }
    return value;
  }

  int _evaluate(ConnectFourGame g, int me) {
    var score = 0;
    final b = g.board;
    final center = g.columns ~/ 2;
    for (var r = 0; r < g.rows; r++) {
      if (b[r][center] == me) score += 3;
    }
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.columns; c++) {
        for (final (dr, dc) in dirs) {
          final er = r + dr * 3, ec = c + dc * 3;
          if (er < 0 || er >= g.rows || ec < 0 || ec >= g.columns) {
            continue;
          }
          var mine = 0, theirs = 0;
          for (var i = 0; i < 4; i++) {
            final v = b[r + dr * i][c + dc * i];
            if (v == me) {
              mine++;
            } else if (v != 0) {
              theirs++;
            }
          }
          if (theirs == 0) score += const [0, 1, 5, 50, 0][mine];
          if (mine == 0) score -= const [0, 1, 6, 60, 0][theirs];
        }
      }
    }
    return score;
  }
}
