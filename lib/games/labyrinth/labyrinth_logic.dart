import 'dart:collection';
import 'dart:math';

import '../../core/sphere.dart';

import 'dart:typed_data';

/// Axis aligned wall rectangle in board units.
class Wall {
  const Wall(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
}

class Hole {
  const Hole(this.x, this.y, {this.radius = 0.045});
  final double x, y, radius;
}

class LabyrinthLevel {
  const LabyrinthLevel({
    required this.name,
    required this.start,
    required this.goal,
    required this.walls,
    required this.holes,
    this.frame = true,
  });

  /// Without a frame the ball can roll off the board.
  final bool frame;
  final String name;
  final (double, double) start;
  final Hole goal;
  final List<Wall> walls;
  final List<Hole> holes;
}

/// The board is [boardWidth] × [boardHeight] units (portrait, like a phone).
const double boardWidth = 1.0;
const double boardHeight = 1.6;
const double _t = 0.025; // wall thickness

List<Wall> _frame() => const [
  Wall(0, 0, boardWidth, _t),
  Wall(0, boardHeight - _t, boardWidth, boardHeight),
  Wall(0, 0, _t, boardHeight),
  Wall(boardWidth - _t, 0, boardWidth, boardHeight),
];

Wall _h(double x1, double x2, double y) => Wall(x1, y - _t / 2, x2, y + _t / 2);
Wall _v(double x, double y1, double y2) => Wall(x - _t / 2, y1, x + _t / 2, y2);

final List<LabyrinthLevel> _handmadeLevels = [
  LabyrinthLevel(
    name: 'Aufwärmen',
    start: (0.15, 0.12),
    goal: const Hole(0.85, 1.48),
    walls: [..._frame(), _h(0, 0.7, 0.45), _h(0.3, 1, 0.9), _h(0, 0.7, 1.25)],
    holes: const [],
  ),
  LabyrinthLevel(
    name: 'Erste Löcher',
    start: (0.12, 0.12),
    goal: const Hole(0.12, 1.48),
    walls: [..._frame(), _h(0, 0.72, 0.4), _h(0.28, 1, 0.8), _h(0, 0.72, 1.2)],
    holes: const [
      Hole(0.88, 0.2),
      Hole(0.5, 0.6),
      Hole(0.12, 1.0),
      Hole(0.55, 1.4),
    ],
  ),
  LabyrinthLevel(
    name: 'Zickzack',
    start: (0.1, 0.1),
    goal: const Hole(0.9, 1.5),
    walls: [..._frame(), _v(0.25, 0, 1.3), _v(0.5, 0.3, 1.6), _v(0.75, 0, 1.3)],
    holes: const [
      Hole(0.125, 0.8),
      Hole(0.375, 0.2),
      Hole(0.375, 1.0),
      Hole(0.625, 0.55),
      Hole(0.625, 1.2),
      Hole(0.875, 0.75),
    ],
  ),
  LabyrinthLevel(
    name: 'Kammern',
    start: (0.5, 0.1),
    goal: const Hole(0.5, 0.85),
    walls: [
      ..._frame(),
      // Outer chamber, open at the bottom.
      _h(0.2, 0.8, 0.3),
      _v(0.2, 0.3, 1.3),
      _v(0.8, 0.3, 1.3),
      _h(0.2, 0.42, 1.3),
      _h(0.58, 0.8, 1.3),
      // Inner chamber with the goal, open at the top.
      _h(0.35, 0.42, 0.55),
      _h(0.58, 0.65, 0.55),
      _v(0.35, 0.55, 1.05),
      _v(0.65, 0.55, 1.05),
      _h(0.35, 0.65, 1.05),
    ],
    holes: const [
      Hole(0.06, 0.8, radius: 0.035),
      Hole(0.94, 1.0, radius: 0.035),
      Hole(0.5, 1.45, radius: 0.035),
      Hole(0.5, 1.15, radius: 0.035),
      Hole(0.27, 0.4, radius: 0.035),
      Hole(0.73, 0.45, radius: 0.035),
    ],
  ),
  LabyrinthLevel(
    name: 'Meisterstück',
    start: (0.08, 1.52),
    goal: const Hole(0.92, 0.08, radius: 0.04),
    walls: [
      ..._frame(),
      _h(0, 0.8, 1.38),
      _h(0.2, 1, 1.12),
      _h(0, 0.8, 0.86),
      _h(0.2, 1, 0.6),
      _h(0, 0.8, 0.34),
      _v(0.5, 1.12, 1.25),
      _v(0.5, 0.6, 0.73),
    ],
    holes: const [
      Hole(0.35, 1.48),
      Hole(0.92, 1.3),
      Hole(0.3, 1.25),
      Hole(0.7, 1.0),
      Hole(0.08, 0.98),
      Hole(0.4, 0.74),
      Hole(0.92, 0.75),
      Hole(0.6, 0.47),
      Hole(0.08, 0.48),
      Hole(0.5, 0.2),
      Hole(0.25, 0.1),
    ],
  ),
];

/// All levels: five hand made ones, then generated mazes that get bigger
/// and have more holes.
/// All levels. Generated levels are built lazily when first used, because
/// checking every trap hole for solvability takes a moment.
final List<LabyrinthLevel> labyrinthLevels = _LazyLevels([
  for (final l in _handmadeLevels) () => l,
  for (var i = 0; i < _mazeSpecs.length; i++)
    () => generateMazeLevel(
      name: _mazeSpecs[i].$1,
      cols: _mazeSpecs[i].$2,
      rows: _mazeSpecs[i].$3,
      holeShare: _mazeSpecs[i].$4,
      pathTraps: _mazeSpecs[i].$5,
      seed: 1000 + i * 37,
    ),
  for (final l in _edgeLevels) () => l,
  for (var i = 0; i < _holeFieldSpecs.length; i++)
    () => generateMazeLevel(
      name: _holeFieldSpecs[i].$1,
      cols: _holeFieldSpecs[i].$2,
      rows: _holeFieldSpecs[i].$3,
      holeShare: 1.0,
      pathTraps: _holeFieldSpecs[i].$5,
      seed: 5000 + i * 53,
      mazeWalls: false,
      frame: _holeFieldSpecs[i].$4,
    ),
]);

class _LazyLevels extends ListBase<LabyrinthLevel> {
  _LazyLevels(this._builders) : _cache = List.filled(_builders.length, null);
  final List<LabyrinthLevel Function()> _builders;
  final List<LabyrinthLevel?> _cache;

  @override
  int get length => _builders.length;
  @override
  set length(int _) => throw UnsupportedError('fixed');
  @override
  LabyrinthLevel operator [](int i) => _cache[i] ??= _builders[i]();
  @override
  void operator []=(int i, LabyrinthLevel v) => throw UnsupportedError('fixed');
}

/// Hole fields: no walls at all, only a winding path between holes.
/// (name, columns, rows, with frame, share of path cells with a trap hole)
const _holeFieldSpecs = [
  ('Lochfeld', 4, 6, true, 0.6),
  ('Pfad der Löcher', 5, 7, true, 0.8),
  ('Freier Fall', 4, 7, false, 0.8),
  ('Drahtseil', 5, 8, false, 1.0),
  ('Abgrund', 6, 9, false, 1.0),
  ('Meister ohne Netz', 7, 11, false, 1.0),
];

/// Levels without a solid border: the ball can roll off the board.
final List<LabyrinthLevel> _edgeLevels = [
  LabyrinthLevel(
    name: 'Ohne Rand',
    start: (0.5, 0.12),
    goal: const Hole(0.5, 1.45),
    frame: false,
    walls: [_h(0.2, 0.8, 0.45), _h(0.2, 0.8, 0.95)],
    holes: const [Hole(0.5, 0.7, radius: 0.05), Hole(0.5, 1.2, radius: 0.05)],
  ),
  LabyrinthLevel(
    name: 'Lochrand',
    start: (0.2, 0.15),
    goal: const Hole(0.8, 1.45),
    frame: false,
    walls: [_h(0.1, 0.65, 0.5), _h(0.35, 0.9, 1.0)],
    holes: [
      // A ring of holes instead of a wooden border.
      for (var i = 0; i < 10; i++) Hole(0.05 + i * 0.1, 0.04, radius: 0.04),
      for (var i = 0; i < 10; i++) Hole(0.05 + i * 0.1, 1.56, radius: 0.04),
      for (var i = 1; i < 16; i++) Hole(0.04, i * 0.1, radius: 0.04),
      for (var i = 1; i < 16; i++) Hole(0.96, i * 0.1, radius: 0.04),
      const Hole(0.8, 0.75, radius: 0.04),
      const Hole(0.2, 1.25, radius: 0.04),
    ].where((h) => !(h.y > 1.5 && (h.x - 0.8).abs() < 0.1)).toList(),
  ),
  LabyrinthLevel(
    name: 'Slalom',
    start: (0.5, 0.08),
    goal: const Hole(0.5, 1.52),
    frame: false,
    walls: const [],
    holes: [
      for (var i = 0; i < 7; i++)
        Hole(i.isEven ? 0.32 : 0.68, 0.25 + i * 0.18, radius: 0.12),
    ],
  ),
];

/// (name, columns, rows, share of side cells with a hole,
///  share of path cells with a trap hole right next to the way)
const _mazeSpecs = [
  ('Irrgarten', 4, 6, 0.0, 0.0),
  ('Sackgassen', 4, 7, 0.35, 0.45),
  ('Wendeltreppe', 5, 7, 0.4, 0.6),
  ('Fallenstellerei', 5, 8, 0.55, 0.75),
  ('Holzwurm', 5, 9, 0.6, 0.85),
  ('Engpass', 6, 9, 0.6, 0.9),
  ('Lochfraß', 6, 10, 0.7, 0.95),
  ('Schweizer Käse', 6, 10, 0.85, 1.0),
  ('Geduldsprobe', 7, 11, 0.7, 1.0),
  ('Nervenkitzel', 7, 11, 0.85, 1.0),
  ('Zitterpartie', 7, 11, 1.0, 1.0),
  ('Großmeister', 7, 11, 1.0, 1.0),
];

/// Builds a maze level with a recursive backtracker. Holes are only put
/// into cells off the solution path (side passages and dead ends), so every
/// level is solvable; the many dead ends with holes make it tricky.
LabyrinthLevel generateMazeLevel({
  required String name,
  required int cols,
  required int rows,
  required double holeShare,
  required int seed,
  double pathTraps = 0,
  bool mazeWalls = true,
  bool frame = true,
}) {
  final r = Random(seed);
  const inner = _t; // frame thickness
  final cw = (boardWidth - 2 * inner) / cols;
  final ch = (boardHeight - 2 * inner) / rows;
  // Open passages: right[c][r] = wall to the right is open, down likewise.
  final right = List.generate(cols, (_) => List.filled(rows, false));
  final down = List.generate(cols, (_) => List.filled(rows, false));
  final visited = List.generate(cols, (_) => List.filled(rows, false));
  final parent = <(int, int), (int, int)>{};
  final stack = <(int, int)>[(0, 0)];
  visited[0][0] = true;
  while (stack.isNotEmpty) {
    final (c, row) = stack.last;
    final options = <(int, int)>[
      if (c > 0 && !visited[c - 1][row]) (c - 1, row),
      if (c < cols - 1 && !visited[c + 1][row]) (c + 1, row),
      if (row > 0 && !visited[c][row - 1]) (c, row - 1),
      if (row < rows - 1 && !visited[c][row + 1]) (c, row + 1),
    ];
    if (options.isEmpty) {
      stack.removeLast();
      continue;
    }
    final (nc, nr) = options[r.nextInt(options.length)];
    if (nc > c) right[c][row] = true;
    if (nc < c) right[nc][row] = true;
    if (nr > row) down[c][row] = true;
    if (nr < row) down[c][nr] = true;
    visited[nc][nr] = true;
    parent[(nc, nr)] = (c, row);
    stack.add((nc, nr));
  }
  // Goal in the far corner; the solution path is the tree path to it.
  final goalCell = (cols - 1, rows - 1);
  final pathList = <(int, int)>[goalCell];
  var cur = goalCell;
  while (parent.containsKey(cur)) {
    cur = parent[cur]!;
    pathList.add(cur);
  }
  final path = pathList.toSet();
  final ordered = pathList.reversed.toList(); // start -> goal
  double cx(int c) => inner + (c + 0.5) * cw;
  double cy(int row) => inner + (row + 0.5) * ch;
  final walls = <Wall>[if (frame) ..._frame()];
  for (var c = 0; c < cols && mazeWalls; c++) {
    for (var row = 0; row < rows; row++) {
      final x1 = inner + c * cw, y1 = inner + row * ch;
      // Segments are extended by half a thickness so corners are closed.
      if (c < cols - 1 && !right[c][row]) {
        walls.add(_v(x1 + cw, y1 - _t / 2, y1 + ch + _t / 2));
      }
      if (row < rows - 1 && !down[c][row]) {
        walls.add(_h(x1 - _t / 2, x1 + cw + _t / 2, y1 + ch));
      }
    }
  }
  final holeRadius = min(0.042, min(cw, ch) * 0.3);
  final holes = <Hole>[];
  for (var c = 0; c < cols; c++) {
    for (var row = 0; row < rows; row++) {
      if (path.contains((c, row))) continue;
      if (r.nextDouble() < holeShare) {
        // Without walls the holes must almost touch, so the only way
        // through is the path.
        final radius = mazeWalls ? holeRadius : min(cw, ch) * 0.42;
        holes.add(Hole(cx(c), cy(row), radius: radius));
      }
    }
  }
  final start = (cx(0), cy(0));
  final goal = Hole(cx(goalCell.$1), cy(goalCell.$2), radius: holeRadius);
  // Trap holes on the way itself: beside straight passages and in the outer
  // corner of bends (where the ball overshoots). Every trap is only kept if
  // the goal stays reachable.
  final reach = _Reachability(walls, holes);
  for (var i = 2; i < ordered.length - 2; i++) {
    if (r.nextDouble() >= pathTraps) continue;
    final (x0, y0) = ordered[i];
    final (px, py) = ordered[i - 1];
    final (nx, ny) = ordered[i + 1];
    final d1 = (px - x0, py - y0), d2 = (nx - x0, ny - y0);
    double ox, oy;
    if (d1.$1 == -d2.$1 && d1.$2 == -d2.$2) {
      // Straight: put the hole to one side of the lane.
      final side = r.nextBool() ? 1.0 : -1.0;
      ox = d1.$2 != 0 ? side : 0;
      oy = d1.$1 != 0 ? side : 0;
    } else {
      // Bend: outer corner.
      ox = -(d1.$1 + d2.$1).toDouble();
      oy = -(d1.$2 + d2.$2).toDouble();
    }
    // Biggest trap that still leaves a way past it.
    for (final (offset, scale) in const [
      (0.22, 1.0),
      (0.27, 0.85),
      (0.3, 0.7),
      (0.33, 0.55),
    ]) {
      final trap = Hole(
        cx(x0) + ox * cw * offset,
        cy(y0) + oy * ch * offset,
        radius: holeRadius * scale,
      );
      if (reach.tryAdd(trap, start, goal)) {
        holes.add(trap);
        break;
      }
    }
  }
  return LabyrinthLevel(
    name: name,
    start: start,
    goal: goal,
    walls: walls,
    holes: holes,
    frame: frame,
  );
}

/// Grid of positions the ball centre can occupy, used to check that the
/// goal stays reachable when adding holes.
class _Reachability {
  _Reachability(List<Wall> walls, List<Hole> holes) {
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final x = i * step, y = j * step;
        for (final wall in walls) {
          final cx = x.clamp(wall.left, wall.right);
          final cy = y.clamp(wall.top, wall.bottom);
          final dx = x - cx, dy = y - cy;
          if (dx * dx + dy * dy < _r2) {
            blocked[j * w + i] = 1;
            break;
          }
        }
      }
    }
    for (final hole in holes) {
      _mark(hole, 1);
    }
  }

  static const step = 0.01;
  static const _ball = LabyrinthGame.radius;
  static const _r2 = _ball * _ball;
  static const margin = 0.012;
  final int w = (boardWidth / step).round() + 1;
  final int h = (boardHeight / step).round() + 1;
  late final Uint8List blocked = Uint8List(w * h);

  List<int> _disk(Hole hole) {
    final rr = hole.radius + margin;
    final cells = <int>[];
    final i0 = max(0, ((hole.x - rr) / step).floor());
    final i1 = min(w - 1, ((hole.x + rr) / step).ceil());
    final j0 = max(0, ((hole.y - rr) / step).floor());
    final j1 = min(h - 1, ((hole.y + rr) / step).ceil());
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        final dx = i * step - hole.x, dy = j * step - hole.y;
        if (dx * dx + dy * dy < rr * rr) cells.add(j * w + i);
      }
    }
    return cells;
  }

  void _mark(Hole hole, int v) {
    for (final c in _disk(hole)) {
      blocked[c] = v;
    }
  }

  /// Adds [hole] if the goal remains reachable from [start].
  bool tryAdd(Hole hole, (double, double) start, Hole goal) {
    final cells = _disk(hole).where((c) => blocked[c] == 0).toList();
    for (final c in cells) {
      blocked[c] = 1;
    }
    if (_reachable(start, goal)) return true;
    for (final c in cells) {
      blocked[c] = 0;
    }
    return false;
  }

  bool _reachable((double, double) start, Hole goal) {
    final s = (start.$2 / step).round() * w + (start.$1 / step).round();
    if (blocked[s] == 1) return false;
    final seen = Uint8List(w * h)..[s] = 1;
    final queue = <int>[s];
    final gr2 = goal.radius * goal.radius;
    for (var q = 0; q < queue.length; q++) {
      final c = queue[q];
      final i = c % w, j = c ~/ w;
      final dx = i * step - goal.x, dy = j * step - goal.y;
      if (dx * dx + dy * dy < gr2) return true;
      for (final n in [
        if (i > 0) c - 1,
        if (i < w - 1) c + 1,
        if (j > 0) c - w,
        if (j < h - 1) c + w,
      ]) {
        if (seen[n] == 0 && blocked[n] == 0) {
          seen[n] = 1;
          queue.add(n);
        }
      }
    }
    return false;
  }
}

enum BallState { rolling, fell, won }

/// Physics of the tilting wooden labyrinth.
class LabyrinthGame {
  LabyrinthGame(this.level) {
    reset();
  }

  final LabyrinthLevel level;
  static const double radius = 0.03;
  static const double gravity = 2.2; // board units / s² at full tilt
  /// Rolling friction per second (lower in the secret nightmare mode).
  double damping = 0.6;

  /// Bounce off walls (higher for the secret rubber ball).
  double restitution = 0.35;

  double x = 0, y = 0, vx = 0, vy = 0;
  BallState state = BallState.rolling;

  /// Strongest wall hit (change of speed) since the last [takeImpact].
  double impact = 0;

  double takeImpact() {
    final i = impact;
    impact = 0;
    return i;
  }

  /// How the ball has turned (only for drawing).
  final SphereOrientation orientation = SphereOrientation(axisAngle: 0.6);
  double elapsed = 0;

  void reset() {
    x = level.start.$1;
    y = level.start.$2;
    vx = 0;
    vy = 0;
    elapsed = 0;
    state = BallState.rolling;
  }

  /// Advances the simulation. [tiltX]/[tiltY] are in g (-1..1), positive
  /// values accelerate the ball to the right / down on screen.
  void step(double dt, double tiltX, double tiltY) {
    if (state != BallState.rolling) return;
    elapsed += dt;
    // Sub-steps prevent tunneling through thin walls.
    final steps = max(1, (dt / 0.004).ceil());
    final h = dt / steps;
    for (var i = 0; i < steps && state == BallState.rolling; i++) {
      vx += tiltX.clamp(-1.0, 1.0) * gravity * h;
      vy += tiltY.clamp(-1.0, 1.0) * gravity * h;
      final f = pow(1 - damping, h).toDouble();
      vx *= f;
      vy *= f;
      x += vx * h;
      y += vy * h;
      orientation.roll(vx * h, vy * h, radius);
      final bx = vx, by = vy;
      for (final w in level.walls) {
        _collide(w);
      }
      impact = max(impact, max((vx - bx).abs(), (vy - by).abs()));
      _checkHoles();
      if (state == BallState.rolling &&
          (x < 0 || y < 0 || x > boardWidth || y > boardHeight)) {
        // Rolled off the edge of a board without frame.
        state = BallState.fell;
        x = x.clamp(0.0, boardWidth);
        y = y.clamp(0.0, boardHeight);
      }
    }
  }

  void _collide(Wall w) {
    final cx = x.clamp(w.left, w.right);
    final cy = y.clamp(w.top, w.bottom);
    final dx = x - cx, dy = y - cy;
    final d2 = dx * dx + dy * dy;
    if (d2 >= radius * radius) return;
    if (d2 == 0) {
      // Center inside the wall: push out along the smallest overlap.
      final pushes = [x - w.left, w.right - x, y - w.top, w.bottom - y];
      final m = pushes.reduce(min);
      if (m == pushes[0]) {
        x = w.left - radius;
        vx = -vx.abs() * restitution;
      } else if (m == pushes[1]) {
        x = w.right + radius;
        vx = vx.abs() * restitution;
      } else if (m == pushes[2]) {
        y = w.top - radius;
        vy = -vy.abs() * restitution;
      } else {
        y = w.bottom + radius;
        vy = vy.abs() * restitution;
      }
      return;
    }
    final d = sqrt(d2);
    final nx = dx / d, ny = dy / d;
    x = cx + nx * radius;
    y = cy + ny * radius;
    final vn = vx * nx + vy * ny;
    if (vn < 0) {
      vx -= (1 + restitution) * vn * nx;
      vy -= (1 + restitution) * vn * ny;
    }
  }

  void _checkHoles() {
    bool inside(Hole h) {
      final dx = x - h.x, dy = y - h.y;
      // The ball drops once its center is above the hole.
      return dx * dx + dy * dy < h.radius * h.radius;
    }

    if (inside(level.goal)) {
      state = BallState.won;
      x = level.goal.x;
      y = level.goal.y;
      return;
    }
    for (final h in level.holes) {
      if (inside(h)) {
        state = BallState.fell;
        x = h.x;
        y = h.y;
        return;
      }
    }
  }
}
