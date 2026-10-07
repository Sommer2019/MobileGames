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

/// A chain or loop of open boxes in the endgame: every box in it has two
/// sides left, so the first line drawn in it gives all of it away.
class BoxChain {
  BoxChain(this.boxes, {required this.loop});
  final List<int> boxes;
  final bool loop;
  int get length => boxes.length;
}

/// Chains and loops of the boxes that are still open (null when some box
/// has three or four sides left – then it is no clean endgame yet). Boxes
/// with only one side left ("hot", can be taken now) are returned apart.
({List<BoxChain> cold, List<List<int>> hot})? boxChains(BoxesGame g) {
  final seen = <int>{};
  final cold = <BoxChain>[];
  final hot = <List<int>>[];
  int left(int b) => 4 - g.sidesDrawn(b);
  for (var start = 0; start < g.owner.length; start++) {
    if (g.owner[start] >= 0 || seen.contains(start)) continue;
    final comp = <int>[];
    final queue = [start];
    seen.add(start);
    var internal = 0;
    while (queue.isNotEmpty) {
      final b = queue.removeLast();
      comp.add(b);
      if (left(b) > 2) return null;
      for (final l in g.sidesOf(b)) {
        if (g.lines[l]) continue;
        for (final o in g.boxesOf(l)) {
          if (o == b) continue;
          internal++;
          if (seen.add(o)) queue.add(o);
        }
      }
    }
    internal ~/= 2; // every shared line was counted from both sides
    if (comp.any((b) => left(b) == 1)) {
      hot.add(comp);
    } else {
      cold.add(BoxChain(comp, loop: internal == comp.length));
    }
  }
  return (cold: cold, hot: hot);
}

/// Value of an endgame for the player who has to open one of the chains or
/// loops [lengths] (true = loop): own boxes minus the other's boxes when
/// both play well. The other player takes everything, or keeps control by
/// leaving the last 2 boxes of a chain (4 of a loop) to the opener.
int endgameValue(List<(int, bool)> parts, [Map<String, int>? memo]) {
  if (parts.isEmpty) return 0;
  memo ??= {};
  final sorted = [...parts]
    ..sort(
      (a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : (a.$2 ? 1 : 0) - (b.$2 ? 1 : 0),
    );
  final key = sorted.map((p) => '${p.$1}${p.$2 ? 'L' : 'C'}').join(',');
  final known = memo[key];
  if (known != null) return known;
  var best = -1 << 30;
  final tried = <String>{};
  for (var i = 0; i < sorted.length; i++) {
    final (n, loop) = sorted[i];
    if (!tried.add('$n$loop')) continue;
    final rest = [...sorted]..removeAt(i);
    final f = endgameValue(rest, memo);
    var v = -n - f; // the other takes all and must open the next one
    if (loop && n >= 4) {
      v = min(v, 8 - n + f); // takes n − 4, leaves 4, keeps control
    } else if (!loop && n >= 3) {
      v = min(v, 4 - n + f); // takes n − 2, leaves 2, keeps control
    }
    if (v > best) best = v;
  }
  memo[key] = best;
  return best;
}

/// Computer player: takes boxes, avoids giving away boxes, and if it has
/// to, gives away as few as possible. In the endgame it keeps control like
/// a good player: it leaves the last two boxes of a chain to the other
/// player when that wins the bigger chains afterwards, and opens the chain
/// that costs least. [strong] ("Käsekästchen-Profi") also plays the very
/// end by full search.
class BoxesAi {
  BoxesAi({Random? random, this.strong = false}) : _random = random ?? Random();
  final Random _random;
  final bool strong;

  int move(BoxesGame g) {
    final open = g.openLines;
    if (strong && g.players == 2 && open.length <= 14) return _exact(g);
    final chains = g.players == 2 ? boxChains(g) : null;
    // 1. Close a box (or in the endgame decline the last ones on purpose).
    final capture = [
      for (final l in open)
        if (g.boxesOf(l).any((b) => g.sidesDrawn(b) == 3)) l,
    ];
    if (capture.isNotEmpty) {
      if (chains != null) {
        final keep = _keepControl(g, chains.cold, chains.hot);
        if (keep != null) return keep;
      }
      return capture.first;
    }
    // 2. A line that does not give a third side to any box.
    final safe = [
      for (final l in open)
        if (g.boxesOf(l).every((b) => g.sidesDrawn(b) < 2)) l,
    ];
    if (safe.isNotEmpty) return safe[_random.nextInt(safe.length)];
    // 3. Endgame: open the chain or loop that costs least.
    if (chains != null && chains.hot.isEmpty && chains.cold.isNotEmpty) {
      return _openBest(g, chains.cold);
    }
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

  /// While taking boxes in the endgame: the line that hands the last two
  /// boxes of a chain (four of a loop) to the other player, if keeping
  /// control that way is worth more than taking them. Null: just take.
  int? _keepControl(BoxesGame g, List<BoxChain> cold, List<List<int>> hot) {
    // Only decide on the last chain being taken; take the others first.
    if (hot.length != 1 || cold.isEmpty) return null;
    final comp = hot.single;
    int left(int b) => 4 - g.sidesDrawn(b);
    final ends = comp.where((b) => left(b) == 1).toList();
    final rest = [for (final c in cold) (c.length, c.loop)];
    final f = endgameValue(rest);
    List<int> openSides(int b) => [
      for (final l in g.sidesOf(b))
        if (!g.lines[l]) l,
    ];
    if (ends.length == 1 && comp.length == 2) {
      // Chain end: A (one side left) – B (two sides left) – border.
      final a = ends.single;
      final b = comp.firstWhere((x) => x != a);
      final takeAll = 2 + f; // then we have to open the next chain
      final decline = -2 - f; // they get 2 and have to open
      if (decline <= takeAll) return null;
      final shared = openSides(a).single;
      return openSides(b).firstWhere((l) => l != shared);
    }
    if (ends.length == 2 && comp.length == 4) {
      // Opened loop: A1 – B – C – A2; the middle line leaves two pairs.
      final takeAll = 4 + f;
      final decline = -4 - f;
      if (decline <= takeAll) return null;
      final inner = comp.where((b) => left(b) == 2).toList();
      if (inner.length != 2) return null;
      final middle = openSides(inner[0]).where(openSides(inner[1]).contains);
      return middle.isEmpty ? null : middle.first;
    }
    return null;
  }

  /// Opens the chain or loop that is best to give away, so that a pair is
  /// opened in its middle (then it cannot be used to keep control).
  int _openBest(BoxesGame g, List<BoxChain> cold) {
    final memo = <String, int>{};
    BoxChain? best;
    var bestValue = -1 << 30;
    for (var i = 0; i < cold.length; i++) {
      final c = cold[i];
      final rest = [
        for (var j = 0; j < cold.length; j++)
          if (j != i) (cold[j].length, cold[j].loop),
      ];
      final f = endgameValue(rest, memo);
      var v = -c.length - f;
      if (c.loop && c.length >= 4) v = min(v, 8 - c.length + f);
      if (!c.loop && c.length >= 3) v = min(v, 4 - c.length + f);
      if (v > bestValue) {
        bestValue = v;
        best = c;
      }
    }
    final c = best!;
    List<int> openSides(int b) => [
      for (final l in g.sidesOf(b))
        if (!g.lines[l]) l,
    ];
    if (!c.loop && c.length == 2) {
      final shared = openSides(c.boxes[0])
          .where(openSides(c.boxes[1]).contains);
      if (shared.isNotEmpty) return shared.first;
    }
    return openSides(c.boxes.first).first;
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
