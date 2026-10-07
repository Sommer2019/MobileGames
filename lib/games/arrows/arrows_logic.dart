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

  /// Builds level [number] (1, 2, …); the same number gives the same level.
  factory ArrowsLevel.generate(int number) {
    final w = min(6 + number ~/ 6, 15);
    final h = min(8 + number ~/ 4, 22);
    final maxLen = min(4 + number ~/ 5, 14);
    final fill = min(0.55 + number * 0.006, 0.82);
    return ArrowsLevel.random(
      w,
      h,
      Random(number * 7919 + 17),
      maxLen: maxLen,
      fill: fill,
    );
  }

  factory ArrowsLevel.random(
    int width,
    int height,
    Random r, {
    int maxLen = 8,
    double fill = 0.7,
  }) {
    final owner = List.generate(height, (_) => List.filled(width, -1));
    bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
    final arrows = <Arrow>[];
    var failures = 0;
    var used = 0;
    while (used < width * height * fill && failures < 4000) {
      final hx = r.nextInt(width), hy = r.nextInt(height);
      final d = r.nextInt(4);
      final (dx, dy) = arrowDirs[d];
      // The way out (head ray) must be free of all arrows so far.
      var free = owner[hy][hx] < 0;
      final ray = <(int, int)>{};
      for (
        var x = hx + dx, y = hy + dy;
        free && inside(x, y);
        x += dx, y += dy
      ) {
        if (owner[y][x] >= 0) free = false;
        ray.add((x, y));
      }
      final px = hx - dx, py = hy - dy;
      if (!free || !inside(px, py) || owner[py][px] >= 0) {
        failures++;
        continue;
      }
      // Grow the body backwards with a wandering walk.
      final path = [(hx, hy), (px, py)];
      final taken = {(hx, hy), (px, py)};
      final len = 2 + r.nextInt(maxLen - 1);
      var (cx, cy) = (px, py);
      var (ldx, ldy) = (-dx, -dy);
      while (path.length < len) {
        final options = <(int, int)>[];
        for (final (ex, ey) in arrowDirs) {
          final nx = cx + ex, ny = cy + ey;
          if (!inside(nx, ny) || owner[ny][nx] >= 0) continue;
          if (taken.contains((nx, ny)) || ray.contains((nx, ny))) continue;
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
      final arrow = Arrow(path.reversed.toList());
      for (final (x, y) in arrow.cells) {
        owner[y][x] = arrows.length;
      }
      arrows.add(arrow);
      used += path.length;
      failures = 0;
    }
    return ArrowsLevel(width, height, arrows);
  }

  final int width;
  final int height;
  final List<Arrow> arrows;

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
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
