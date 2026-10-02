import 'dart:math';

class Ball {
  Ball(this.number, this.x, this.y);
  final int number; // 0 = cue ball
  double x, y;
  double vx = 0, vy = 0;
  bool pocketed = false;

  bool get moving => vx * vx + vy * vy > 1e-8;
}

/// Single player pool: pocket all 15 balls with as few shots as possible.
/// Pocketing the cue ball costs a penalty shot.
class BilliardGame {
  BilliardGame() {
    rack();
  }

  static const double width = 2.0;
  static const double height = 1.0;
  static const double radius = 0.028;
  static const double pocketRadius = 0.062;
  static const double friction = 0.45; // linear deceleration, units/s²
  static const double cushion = 0.8;
  static const double maxSpeed = 4.0;

  static const List<(double, double)> pockets = [
    (0, 0),
    (width / 2, -0.01),
    (width, 0),
    (0, height),
    (width / 2, height + 0.01),
    (width, height),
  ];

  final List<Ball> balls = [];
  int shots = 0;
  int fouls = 0;
  final List<int> pocketedThisShot = [];

  Ball get cue => balls.first;
  bool get moving => balls.any((b) => !b.pocketed && b.moving);
  int get remaining => balls.where((b) => b.number != 0 && !b.pocketed).length;
  bool get won => remaining == 0;
  int get score => shots + fouls;

  void rack() {
    balls
      ..clear()
      ..add(Ball(0, width * 0.25, height / 2));
    // Classic triangle with the 8 in the middle.
    const order = [1, 9, 2, 10, 8, 3, 11, 7, 14, 4, 5, 13, 15, 6, 12];
    var i = 0;
    final d = radius * 2 + 0.002;
    for (var row = 0; row < 5; row++) {
      for (var k = 0; k <= row; k++) {
        balls.add(
          Ball(
            order[i++],
            width * 0.7 + row * d * sqrt(3) / 2,
            height / 2 + (k - row / 2) * d,
          ),
        );
      }
    }
    shots = 0;
    fouls = 0;
  }

  /// Shoots the cue ball. [angle] in radians, [power] 0..1.
  bool shoot(double angle, double power) {
    if (moving || cue.pocketed || won) return false;
    final speed = power.clamp(0.0, 1.0) * maxSpeed;
    cue.vx = cos(angle) * speed;
    cue.vy = sin(angle) * speed;
    shots++;
    pocketedThisShot.clear();
    return true;
  }

  /// Advances the simulation by [dt] seconds.
  void step(double dt) {
    final steps = max(1, (dt / 0.002).ceil());
    final h = dt / steps;
    for (var s = 0; s < steps; s++) {
      _substep(h);
    }
    if (!moving && cue.pocketed) _respawnCue();
  }

  void _substep(double h) {
    final active = balls.where((b) => !b.pocketed).toList();
    for (final b in active) {
      final v = sqrt(b.vx * b.vx + b.vy * b.vy);
      if (v > 0) {
        final nv = max(0.0, v - friction * h);
        if (nv < 0.005) {
          b.vx = 0;
          b.vy = 0;
        } else {
          b.vx *= nv / v;
          b.vy *= nv / v;
        }
      }
      b.x += b.vx * h;
      b.y += b.vy * h;
    }
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        _collide(active[i], active[j]);
      }
    }
    for (final b in active) {
      for (final (px, py) in pockets) {
        final dx = b.x - px, dy = b.y - py;
        if (dx * dx + dy * dy < pocketRadius * pocketRadius) {
          b.pocketed = true;
          b.vx = 0;
          b.vy = 0;
          if (b.number == 0) {
            fouls++;
          } else {
            pocketedThisShot.add(b.number);
          }
          break;
        }
      }
      if (b.pocketed) continue;
      if (b.x < radius) {
        b.x = radius;
        b.vx = b.vx.abs() * cushion;
      } else if (b.x > width - radius) {
        b.x = width - radius;
        b.vx = -b.vx.abs() * cushion;
      }
      if (b.y < radius) {
        b.y = radius;
        b.vy = b.vy.abs() * cushion;
      } else if (b.y > height - radius) {
        b.y = height - radius;
        b.vy = -b.vy.abs() * cushion;
      }
    }
  }

  void _collide(Ball a, Ball b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final d2 = dx * dx + dy * dy;
    const minD = radius * 2;
    if (d2 >= minD * minD || d2 == 0) return;
    final d = sqrt(d2);
    final nx = dx / d, ny = dy / d;
    // Separate overlapping balls.
    final overlap = (minD - d) / 2;
    a.x -= nx * overlap;
    a.y -= ny * overlap;
    b.x += nx * overlap;
    b.y += ny * overlap;
    // Elastic collision of equal masses: exchange the normal components.
    final rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
    if (rel <= 0) return;
    const e = 0.95;
    final impulse = rel * (1 + e) / 2;
    a.vx -= impulse * nx;
    a.vy -= impulse * ny;
    b.vx += impulse * nx;
    b.vy += impulse * ny;
  }

  void _respawnCue() {
    var x = width * 0.25;
    const y = height / 2;
    bool blocked(double px) => balls.any(
      (b) =>
          b != cue &&
          !b.pocketed &&
          pow(b.x - px, 2) + pow(b.y - y, 2) < pow(radius * 2.2, 2),
    );
    while (blocked(x) && x > radius * 2) {
      x -= radius;
    }
    cue
      ..pocketed = false
      ..x = x
      ..y = y
      ..vx = 0
      ..vy = 0;
  }
}
