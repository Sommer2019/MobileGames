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

  /// Number of the first ball the cue ball touched during the last shot.
  int? firstHit;

  /// Whether the cue ball was pocketed during the last shot.
  bool scratched = false;

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
    firstHit = null;
    scratched = false;
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
            scratched = true;
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
    if (firstHit == null) {
      if (a.number == 0) firstHit = b.number;
      if (b.number == 0) firstHit = a.number;
    }
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

  /// Serialises the positions of all balls (for online play).
  List<List<num>> snapshot() => [
    for (final b in balls) [b.x, b.y, b.pocketed ? 1 : 0],
  ];

  void restore(List<dynamic> snap) {
    for (var i = 0; i < balls.length && i < snap.length; i++) {
      final s = snap[i] as List;
      balls[i]
        ..x = (s[0] as num).toDouble()
        ..y = (s[1] as num).toDouble()
        ..pocketed = s[2] == 1
        ..vx = 0
        ..vy = 0;
    }
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

enum BallGroup { solids, stripes }

BallGroup? groupOf(int n) => n >= 1 && n <= 7
    ? BallGroup.solids
    : (n >= 9 && n <= 15 ? BallGroup.stripes : null);

/// Simplified 8-ball rules for two players.
///
/// Open table until the first ball is legally pocketed. A turn continues
/// while the player legally pockets own balls. Fouls (scratch, touching no
/// ball or a wrong ball first) pass the turn. Pocketing the 8 wins only
/// after all own balls are gone and without a foul, otherwise it loses.
class EightBallRules {
  int current = 0;
  final List<BallGroup?> groups = [null, null];
  int? winner;
  String lastEvent = '';

  bool get isOver => winner != null;

  int remainingOf(BilliardGame g, int player) {
    final group = groups[player];
    if (group == null) return 7;
    return g.balls
        .where((b) => !b.pocketed && groupOf(b.number) == group)
        .length;
  }

  /// Evaluates a finished shot. [pocketed] are the balls pocketed during
  /// the shot (without the cue ball) and [clearedBefore] whether the
  /// shooter had already pocketed all own balls before the shot.
  void evaluate({
    required List<int> pocketed,
    required int? firstHit,
    required bool scratched,
    required bool clearedBefore,
  }) {
    if (isOver) return;
    final me = current, opp = 1 - current;
    final mine = groups[me];
    final foul =
        scratched ||
        firstHit == null ||
        (mine == null && firstHit == 8) ||
        (mine != null &&
            !(groupOf(firstHit) == mine || (clearedBefore && firstHit == 8)));
    if (pocketed.contains(8)) {
      if (clearedBefore && !foul) {
        winner = me;
        lastEvent = 'Die 8 versenkt – Sieg!';
      } else {
        winner = opp;
        lastEvent = 'Die 8 zu früh oder mit Foul versenkt – verloren!';
      }
      return;
    }
    if (mine == null && !foul) {
      final first = pocketed.where((n) => groupOf(n) != null).firstOrNull;
      if (first != null) {
        groups[me] = groupOf(first);
        groups[opp] = groups[me] == BallGroup.solids
            ? BallGroup.stripes
            : BallGroup.solids;
      }
    }
    final own = groups[me];
    final pottedOwn = own != null && pocketed.any((n) => groupOf(n) == own);
    if (foul) {
      lastEvent = scratched
          ? 'Foul: weiße Kugel versenkt'
          : firstHit == null
          ? 'Foul: keine Kugel getroffen'
          : 'Foul: falsche Kugel zuerst getroffen';
      current = opp;
    } else if (pottedOwn) {
      lastEvent = 'Versenkt – nochmal!';
    } else {
      lastEvent = pocketed.isEmpty
          ? 'Nichts versenkt'
          : 'Fremde Kugel versenkt';
      current = opp;
    }
  }
}

enum SoloMode { eightLast, rotation }

extension SoloModeLabel on SoloMode {
  String get label => switch (this) {
    SoloMode.eightLast => '8 zum Schluss',
    SoloMode.rotation => 'Reihenfolge 1–15',
  };
}

/// Rules for playing alone.
///
/// * [SoloMode.eightLast]: like 8-ball, the black 8 must be the last ball.
///   Pocketing it earlier (or together with a scratch) loses the game.
/// * [SoloMode.rotation]: the cue ball must always touch the lowest
///   numbered ball on the table first.
///
/// Fouls (scratch, no ball touched, wrong ball first) cost a penalty point.
class SoloRules {
  SoloRules(this.mode);

  final SoloMode mode;
  bool lost = false;
  int penalties = 0;
  String lastEvent = '';

  /// Ball that has to be hit first (rotation), otherwise null.
  int? target(BilliardGame g) {
    if (mode != SoloMode.rotation) return null;
    final left = g.balls
        .where((b) => b.number != 0 && !b.pocketed)
        .map((b) => b.number);
    return left.isEmpty ? null : left.reduce(min);
  }

  /// Object balls other than the 8 still on the table.
  static int othersLeft(BilliardGame g) => g.balls
      .where((b) => b.number != 0 && b.number != 8 && !b.pocketed)
      .length;

  /// Evaluates a finished shot. [othersBefore] and [targetBefore] are taken
  /// right before the shot.
  void evaluate({
    required List<int> pocketed,
    required int? firstHit,
    required bool scratched,
    required int othersBefore,
    required int? targetBefore,
  }) {
    if (lost) return;
    final events = <String>[];
    if (mode == SoloMode.eightLast && pocketed.contains(8)) {
      if (othersBefore > 0 || scratched) {
        lost = true;
        lastEvent = othersBefore > 0
            ? 'Die 8 zu früh versenkt – verloren!'
            : 'Die 8 mit Foul versenkt – verloren!';
        return;
      }
    }
    if (scratched) events.add('Foul: weiße Kugel versenkt');
    if (firstHit == null) {
      penalties++;
      events.add('Foul: keine Kugel getroffen');
    } else if (mode == SoloMode.rotation &&
        targetBefore != null &&
        firstHit != targetBefore) {
      penalties++;
      events.add('Foul: zuerst die $targetBefore treffen');
    } else if (mode == SoloMode.eightLast &&
        firstHit == 8 &&
        othersBefore > 0) {
      penalties++;
      events.add('Foul: die 8 erst zum Schluss anspielen');
    }
    lastEvent = events.isEmpty
        ? (pocketed.isEmpty ? '' : 'Versenkt: ${pocketed.join(', ')}')
        : events.join(' • ');
  }
}
