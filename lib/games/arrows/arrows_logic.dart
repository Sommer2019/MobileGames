import 'dart:math';

/// Directions: right, down, left, up.
const arrowDirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];

/// One arrow: a path of grid cells from its tail to its head; it leaves the
/// board in the direction of its last segment.
class Arrow {
  Arrow(this.cells);
  final List<(int, int)> cells;

  (int, int) get head => cells.last;

  /// Direction index the head points to.
  int get dir {
    final (hx, hy) = head;
    final (px, py) = cells[cells.length - 2];
    return arrowDirs.indexOf((hx - px, hy - py));
  }
}

/// Arrow puzzle: tap an arrow and it slides out of the board along its
/// head direction. If another arrow is in the way, it bounces back and a
/// heart is lost.
///
/// Levels are built backwards: every new arrow gets a free way out among
/// the arrows already placed, so removing them in reverse order always
/// works. Removing an arrow never blocks another one, so any free arrow
/// is a right move.
class ArrowsLevel {
  ArrowsLevel(this.width, this.height, this.arrows);

  /// Builds level [number] (1, 2, …) of [difficulty]; the same pair
  /// always gives the same level.
  factory ArrowsLevel.generate(
    int number, [
    ArrowsDifficulty difficulty = ArrowsDifficulty.easy,
  ]) {
    final d = difficulty;
    final grow = (number - 1) ~/ d.growEvery;
    final w = min(d.width + grow, d.maxWidth);
    final h = min(d.height + grow * 3 ~/ 2, d.maxHeight);
    final maxLen = min(d.maxLen + grow, d.maxLen + 6);
    // Harder levels: build several and keep the most tangled one.
    ArrowsLevel? best;
    var bestScore = -1;
    for (var c = 0; c < d.candidates; c++) {
      final level = ArrowsLevel.random(
        w,
        h,
        Random(number * 7919 + d.index * 104729 + c * 31 + 17),
        maxLen: maxLen,
        fill: d.fill,
        tangle: d.tangle,
      );
      final score = level.depth * 100 - level.freeAtStart;
      if (score > bestScore) {
        bestScore = score;
        best = level;
      }
    }
    return best!;
  }

  /// Builds a level by placing arrows one after another, each with a free
  /// way out at the time it is placed. With [tangle] > 0 several candidate
  /// arrows are tried per step and the one blocking the most free arrows
  /// is kept – that makes long chains and few free arrows at the start.
  factory ArrowsLevel.random(
    int width,
    int height,
    Random r, {
    int maxLen = 8,
    double fill = 0.7,
    int tangle = 0,
  }) {
    final owner = List.generate(height, (_) => List.filled(width, -1));
    bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
    final arrows = <Arrow>[];
    // Way out of every arrow (cells up to the edge when it was placed).
    final rays = <List<(int, int)>>[];
    bool isFree(int i) => rays[i].every((c) => owner[c.$2][c.$1] < 0);

    /// One random arrow that fits now, with its way out, or null.
    (List<(int, int)>, List<(int, int)>)? candidate() {
      final hx = r.nextInt(width), hy = r.nextInt(height);
      final (dx, dy) = arrowDirs[r.nextInt(4)];
      if (owner[hy][hx] >= 0) return null;
      final ray = <(int, int)>[];
      for (var x = hx + dx, y = hy + dy; inside(x, y); x += dx, y += dy) {
        if (owner[y][x] >= 0) return null;
        ray.add((x, y));
      }
      final px = hx - dx, py = hy - dy;
      if (!inside(px, py) || owner[py][px] >= 0) return null;
      // Grow the body backwards with a wandering walk.
      final path = [(hx, hy), (px, py)];
      final taken = {(hx, hy), (px, py), ...ray};
      // Mostly short and medium arrows, now and then a long one.
      final len = 2 + (pow(r.nextDouble(), 1.6) * (maxLen - 1)).floor();
      var (cx, cy) = (px, py);
      var (ldx, ldy) = (-dx, -dy);
      while (path.length < len) {
        final options = <(int, int)>[];
        for (final (ex, ey) in arrowDirs) {
          final nx = cx + ex, ny = cy + ey;
          if (!inside(nx, ny) || owner[ny][nx] >= 0) continue;
          if (taken.contains((nx, ny))) continue;
          // Straight on is a bit more likely than turning.
          options.add((ex, ey));
          if ((ex, ey) == (ldx, ldy)) options.add((ex, ey));
        }
        if (options.isEmpty) break;
        final (ex, ey) = options[r.nextInt(options.length)];
        cx += ex;
        cy += ey;
        (ldx, ldy) = (ex, ey);
        path.add((cx, cy));
        taken.add((cx, cy));
      }
      return (path.reversed.toList(), ray);
    }

    var failures = 0;
    var used = 0;
    while (used < width * height * fill && failures < 4000) {
      (List<(int, int)>, List<(int, int)>)? best;
      var bestScore = -1.0;
      for (var t = 0; t <= tangle; t++) {
        final c = candidate();
        if (c == null) continue;
        // Free arrows this one would block (newer ones count more, that
        // builds chains), plus a little for length.
        final cells = c.$1.toSet();
        // Long ways out get blocked more easily later on.
        var score = c.$1.length * 0.05 + c.$2.length * 0.12;
        for (var i = 0; i < arrows.length; i++) {
          if (isFree(i) && rays[i].any(cells.contains)) {
            score += 1 + i / arrows.length;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
      if (best == null) {
        failures++;
        continue;
      }
      final arrow = Arrow(best.$1);
      for (final (x, y) in arrow.cells) {
        owner[y][x] = arrows.length;
      }
      arrows.add(arrow);
      rays.add(best.$2);
      used += arrow.cells.length;
      failures = 0;
    }
    return ArrowsLevel(width, height, arrows);
  }

  final int width;
  final int height;
  final List<Arrow> arrows;

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// Arrows that can go right away.
  int get freeAtStart {
    final g = ArrowsGame(this);
    return [for (var i = 0; i < arrows.length; i++) i].where(g.isFree).length;
  }

  /// Rounds needed when every round removes all free arrows at once: the
  /// length of the longest chain of arrows blocking each other.
  int get depth {
    final g = ArrowsGame(this);
    var rounds = 0;
    while (!g.won) {
      final free = [
        for (var i = 0; i < arrows.length; i++)
          if (g.isFree(i)) i,
      ];
      if (free.isEmpty) return 1 << 20; // cannot happen for built levels
      for (final i in free) {
        g.removed[i] = true;
      }
      rounds++;
    }
    return rounds;
  }
}

/// Difficulty settings; each has its own level progress.
enum ArrowsDifficulty {
  easy('Leicht', 7, 10, 9, 13, 6, 0.65, 1, 8, 0),
  medium('Mittel', 10, 14, 12, 18, 9, 0.78, 2, 8, 4),
  hard('Schwer', 12, 17, 14, 21, 10, 0.86, 3, 10, 10),
  extreme('Extrem', 14, 20, 16, 24, 12, 0.9, 4, 12, 20),
  insane('Wahnsinn', 16, 24, 17, 25, 14, 0.94, 5, 15, 40);

  const ArrowsDifficulty(
    this.label,
    this.width,
    this.height,
    this.maxWidth,
    this.maxHeight,
    this.maxLen,
    this.fill,
    this.candidates,
    this.growEvery,
    this.tangle,
  );

  final String label;
  final int width;
  final int height;
  final int maxWidth;
  final int maxHeight;
  final int maxLen;

  /// Share of the grid covered by arrows.
  final double fill;

  /// Levels built per level number; the most tangled one is kept.
  final int candidates;

  /// The grid grows by one every this many levels.
  final int growEvery;

  /// Extra candidate arrows per step, keeping the most blocking one.
  final int tangle;

  /// Mistakes allowed per level.
  int get hearts => switch (this) {
    extreme => 2,
    insane => 1,
    _ => 3,
  };

  /// Hints per level (null: as many as you like).
  int? get hints => switch (this) {
    easy => null,
    medium => 5,
    hard => 3,
    extreme => 2,
    insane => 1,
  };
}

/// A level being played.
class ArrowsGame {
  ArrowsGame(this.level, {this.hearts = 3})
    : removed = List.filled(level.arrows.length, false);

  final ArrowsLevel level;
  final List<bool> removed;
  int hearts;

  int get left => removed.where((r) => !r).length;
  bool get won => left == 0;
  bool get lost => hearts <= 0;

  int? _ownerAt(int x, int y) {
    for (var i = 0; i < level.arrows.length; i++) {
      if (!removed[i] && level.arrows[i].cells.contains((x, y))) return i;
    }
    return null;
  }

  /// Cells the head of arrow [i] can still move before it hits another
  /// arrow, and that arrow (null: the way out is free).
  (int, int?) wayOut(int i) {
    final a = level.arrows[i];
    final (dx, dy) = arrowDirs[a.dir];
    var (x, y) = a.head;
    var steps = 0;
    while (true) {
      x += dx;
      y += dy;
      if (!level.inside(x, y)) return (steps, null);
      final o = _ownerAt(x, y);
      if (o != null && o != i) return (steps, o);
      steps++;
    }
  }

  bool isFree(int i) => !removed[i] && wayOut(i).$2 == null;

  /// Taps arrow [i]: removes it when free, else costs a heart. Returns
  /// whether it got out.
  bool tap(int i) {
    if (removed[i] || won || lost) return false;
    if (isFree(i)) {
      removed[i] = true;
      return true;
    }
    hearts--;
    return false;
  }

  /// Any arrow that can go now (for the hint).
  int? hint() {
    for (var i = 0; i < level.arrows.length; i++) {
      if (isFree(i)) return i;
    }
    return null;
  }
}
