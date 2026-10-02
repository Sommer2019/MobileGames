import 'dart:math';

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
  });

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

final List<LabyrinthLevel> labyrinthLevels = [
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

enum BallState { rolling, fell, won }

/// Physics of the tilting wooden labyrinth.
class LabyrinthGame {
  LabyrinthGame(this.level) {
    reset();
  }

  final LabyrinthLevel level;
  static const double radius = 0.03;
  static const double gravity = 2.2; // board units / s² at full tilt
  static const double damping = 0.6; // rolling friction per second
  static const double restitution = 0.35;

  double x = 0, y = 0, vx = 0, vy = 0;
  BallState state = BallState.rolling;
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
      for (final w in level.walls) {
        _collide(w);
      }
      _checkHoles();
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
