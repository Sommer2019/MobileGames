import 'dart:math';

/// Käsekästchen (dots and boxes) for 2–4 players.
///
/// Players take turns drawing a line between two neighbouring dots. Whoever
/// closes a box owns it and draws again. Most boxes wins.
///
/// Lines have ids: first the horizontal ones row by row
/// ((rows + 1) × cols), then the vertical ones (rows × (cols + 1)).
class BoxesGame {
  BoxesGame({this.players = 2, int? size, int first = 0})
    : cols = size ?? defaultSize(players),
      rows = size ?? defaultSize(players) {
    lines = List.filled(lineCount, false);
    owner = List.filled(rows * cols, -1);
    scores = List.filled(players, 0);
    current = first % players;
  }

  /// Boxes per side: bigger boards for more players.
  static int defaultSize(int players) => const [5, 5, 6, 7][players - 1];

  /// Replays saved [moves].
  factory BoxesGame.replay(
    int players,
    int size,
    List<dynamic> moves, {
    int first = 0,
  }) {
    final g = BoxesGame(players: players, size: size, first: first);
    for (final m in moves) {
      if (!g.draw(m as int)) throw FormatException('illegal line $m');
    }
    return g;
  }

  final int players;
  final int cols, rows;
  late final List<bool> lines;

  /// Owner (player index) of each box, -1 = open.
  late final List<int> owner;
  late final List<int> scores;
  int current = 0;
  final List<int> moves = [];

  int get horizontalCount => (rows + 1) * cols;
  int get lineCount => horizontalCount + rows * (cols + 1);

  bool get isOver => moves.length == lineCount;

  /// Players with the most boxes (several on a tie).
  List<int> get winners {
    final best = scores.reduce(max);
    return [
      for (var i = 0; i < players; i++)
        if (scores[i] == best) i,
    ];
  }

  bool isHorizontal(int line) => line < horizontalCount;

  /// Row and column of a line: horizontal lines run from dot (r, c) to
  /// (r, c + 1), vertical ones from (r, c) to (r + 1, c).
  (int, int) position(int line) {
    if (isHorizontal(line)) return (line ~/ cols, line % cols);
    final v = line - horizontalCount;
    return (v ~/ (cols + 1), v % (cols + 1));
  }

  int horizontal(int r, int c) => r * cols + c;
  int vertical(int r, int c) => horizontalCount + r * (cols + 1) + c;

  /// The (up to two) boxes next to a line.
  List<int> boxesOf(int line) {
    final (r, c) = position(line);
    if (isHorizontal(line)) {
      return [if (r > 0) (r - 1) * cols + c, if (r < rows) r * cols + c];
    }
    return [if (c > 0) r * cols + c - 1, if (c < cols) r * cols + c];
  }

  /// The four lines around a box.
  List<int> sidesOf(int box) {
    final r = box ~/ cols, c = box % cols;
    return [
      horizontal(r, c),
      horizontal(r + 1, c),
      vertical(r, c),
      vertical(r, c + 1),
    ];
  }

  int sidesDrawn(int box) => sidesOf(box).where((l) => lines[l]).length;

  bool canDraw(int line) =>
      !isOver && line >= 0 && line < lineCount && !lines[line];

  /// Draws a line for the current player. Returns false if not allowed.
  bool draw(int line) {
    if (!canDraw(line)) return false;
    lines[line] = true;
    moves.add(line);
    var closed = 0;
    for (final b in boxesOf(line)) {
      if (sidesDrawn(b) == 4) {
        owner[b] = current;
        scores[current]++;
        closed++;
      }
    }
    if (closed == 0) current = (current + 1) % players;
    return true;
  }

  BoxesGame copy() {
    final g = BoxesGame(players: players, size: cols);
    g.lines.setAll(0, lines);
    g.owner.setAll(0, owner);
    g.scores.setAll(0, scores);
    g.current = current;
    g.moves.addAll(moves);
    return g;
  }

  List<int> get openLines => [
    for (var l = 0; l < lineCount; l++)
      if (!lines[l]) l,
  ];
}

/// Computer player: takes boxes, avoids giving away boxes, and if it has
/// to, gives away as few as possible. [strong] ("Käsekästchen-Profi")
/// also plays the end exactly.
class BoxesAi {
  BoxesAi({Random? random, this.strong = false}) : _random = random ?? Random();
  final Random _random;
  final bool strong;

  int move(BoxesGame g) {
    final open = g.openLines;
    // 1. Close a box.
    for (final l in open) {
      if (g.boxesOf(l).any((b) => g.sidesDrawn(b) == 3)) return l;
    }
    // 2. A line that does not give a third side to any box.
    final safe = [
      for (final l in open)
        if (g.boxesOf(l).every((b) => g.sidesDrawn(b) < 2)) l,
    ];
    if (safe.isNotEmpty) return safe[_random.nextInt(safe.length)];
    // 3. Endgame: with two players the strong computer plays it exactly.
    if (strong && g.players == 2 && open.length <= 14) return _exact(g);
    // Otherwise give away the fewest boxes.
    var best = open.first;
    var fewest = 1 << 30;
    for (final l in open) {
      final given = _given(g, l);
      if (given < fewest) {
        fewest = given;
        best = l;
      }
    }
    return best;
  }

  /// How many boxes the opponent can take in a row after [line].
  static int _given(BoxesGame g, int line) {
    final c = g.copy()..draw(line);
    final player = c.current;
    var taken = 0;
    while (!c.isOver && c.current == player) {
      final take = c.openLines.where(
        (l) => c.boxesOf(l).any((b) => c.sidesDrawn(b) == 3),
      );
      if (take.isEmpty) break;
      final before = c.scores[player];
      c.draw(take.first);
      taken += c.scores[player] - before;
    }
    return taken;
  }

  /// Best line by full search with memory (only near the end).
  int _exact(BoxesGame g) {
    final open = g.openLines;
    final memo = <int, int>{};
    var best = open.first;
    var bestScore = -1 << 30;
    for (var i = 0; i < open.length; i++) {
      final gained = _gain(g, open[i]);
      final rest = _value(g, open, (1 << open.length) - 1 & ~(1 << i), memo);
      final s = gained > 0 ? gained + rest : -rest;
      if (s > bestScore) {
        bestScore = s;
        best = open[i];
      }
    }
    return best;
  }

  /// Boxes a line would close now.
  static int _gain(BoxesGame g, int line) =>
      g.boxesOf(line).where((b) => g.sidesDrawn(b) == 3).length;

  /// Best box difference (own − other) for the player to move, when the
  /// lines in [mask] (bits into [open]) are still open.
  int _value(BoxesGame g, List<int> open, int mask, Map<int, int> memo) {
    if (mask == 0) return 0;
    final known = memo[mask];
    if (known != null) return known;
    // Draw the lines that are no longer open on a copy.
    final c = g.copy();
    for (var i = 0; i < open.length; i++) {
      if (mask & (1 << i) == 0) c.lines[open[i]] = true;
    }
    var best = -1 << 30;
    for (var i = 0; i < open.length; i++) {
      if (mask & (1 << i) == 0) continue;
      final gained = _gain(c, open[i]);
      final rest = _value(g, open, mask & ~(1 << i), memo);
      final v = gained > 0 ? gained + rest : gained - rest;
      if (v > best) best = v;
    }
    memo[mask] = best;
    return best;
  }
}
