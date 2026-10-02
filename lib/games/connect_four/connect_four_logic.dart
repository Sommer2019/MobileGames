/// Pure game logic for "4 gewinnt" (Connect Four).
class ConnectFourGame {
  static const int columns = 7;
  static const int rows = 6;

  /// board[row][col], row 0 is the top. 0 = empty, 1 = player one, 2 = player two.
  final List<List<int>> board = List.generate(
    rows,
    (_) => List.filled(columns, 0),
  );

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
    final line = _findLine(row, col);
    if (line != null) {
      winner = currentPlayer;
      winningCells = line;
    } else if (board[0].every((c) => c != 0)) {
      draw = true;
    } else {
      currentPlayer = 3 - currentPlayer;
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
    final g = ConnectFourGame();
    for (var r = 0; r < rows; r++) {
      g.board[r].setAll(0, board[r]);
    }
    g.currentPlayer = currentPlayer;
    g.winner = winner;
    g.draw = draw;
    return g;
  }
}

/// Simple minimax AI for single-device play against the computer.
class ConnectFourAi {
  ConnectFourAi({this.depth = 5});
  final int depth;

  int bestMove(ConnectFourGame game) {
    final me = game.currentPlayer;
    var bestScore = -1 << 30;
    var best = -1;
    for (final col in const [3, 2, 4, 1, 5, 0, 6]) {
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
    for (final col in const [3, 2, 4, 1, 5, 0, 6]) {
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
    for (var r = 0; r < ConnectFourGame.rows; r++) {
      if (b[r][3] == me) score += 3;
    }
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var r = 0; r < ConnectFourGame.rows; r++) {
      for (var c = 0; c < ConnectFourGame.columns; c++) {
        for (final (dr, dc) in dirs) {
          final er = r + dr * 3, ec = c + dc * 3;
          if (er < 0 ||
              er >= ConnectFourGame.rows ||
              ec < 0 ||
              ec >= ConnectFourGame.columns) {
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
