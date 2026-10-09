import 'dart:math';

import '../../core/sphere.dart';

class Ball {
  Ball(this.number, this.x, this.y)
    // Stripes lie in different directions so the rack looks natural.
    : orientation = SphereOrientation(axisAngle: number * 0.7);
  final int number; // 0 = cue ball
  double x, y;
  double vx = 0, vy = 0;
  bool pocketed = false;

  /// How the ball has turned (only for drawing): q is where the number
  /// sits, a the axis of the stripe.
  final SphereOrientation orientation;

  bool get moving => vx * vx + vy * vy > 1e-8;

  /// Rolls the ball over the distance (dx, dy) without slipping.
  void roll(double dx, double dy) =>
      orientation.roll(dx, dy, BilliardGame.radius);
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

  /// Strongest ball/ball and cushion impact (speed) and pocketed balls
  /// since the last [takeSounds], for the sound effects.
  double ballImpact = 0, cushionImpact = 0;
  int pocketedSound = 0;

  /// Returns and clears the collected impacts.
  (double, double, int) takeSounds() {
    final r = (ballImpact, cushionImpact, pocketedSound);
    ballImpact = 0;
    cushionImpact = 0;
    pocketedSound = 0;
    return r;
  }

  Ball get cue => balls.first;
  bool get moving => balls.any((b) => !b.pocketed && b.moving);
  int get remaining => balls.where((b) => b.number != 0 && !b.pocketed).length;
  bool get won => remaining == 0;
  int get score => shots + fouls;

  /// The balls at rest and the counters (for saving the game).
  Map<String, dynamic> toJson() => {
    'balls': [
      for (final b in balls) [b.number, b.x, b.y, if (b.pocketed) 1],
    ],
    'shots': shots,
    'fouls': fouls,
    'cueInHand': cueInHand,
  };

  /// Puts the balls as in a saved game (see [toJson]).
  void load(Map<String, dynamic> j) {
    final list = (j['balls'] as List).cast<List<dynamic>>();
    if (list.isEmpty || list.first[0] != 0) {
      throw const FormatException('no cue ball');
    }
    balls
      ..clear()
      ..addAll([
        for (final b in list)
          Ball(b[0] as int, (b[1] as num).toDouble(), (b[2] as num).toDouble())
            ..pocketed = b.length > 3,
      ]);
    shots = j['shots'] as int;
    fouls = j['fouls'] as int;
    cueInHand = j['cueInHand'] as bool;
  }

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
    // The break is played from anywhere the player likes.
    cueInHand = true;
  }

  /// How strongly follow/draw changes the cue ball's path after contact.
  static const double followFactor = 0.6;

  /// Spin lost per unit of distance the cue ball slides before contact.
  static const double spinDecay = 0.35;

  /// Side spin's effect on cushion rebounds.
  static const double sideFactor = 0.3;

  // Spin of the current shot: [_spinY] > 0 top (follow), < 0 bottom (draw);
  // [_spinX] > 0 right, < 0 left. Both in -1..1.
  double _spinX = 0, _spinY = 0;
  double _dirX = 1, _dirY = 0;

  /// Shoots the cue ball. [angle] in radians, [power] 0..1.
  /// [spinX]/[spinY] is where the cue hits the cue ball (-1..1, y up).
  bool shoot(double angle, double power, {double spinX = 0, double spinY = 0}) {
    if (moving || cue.pocketed || won) return false;
    cueInHand = false;
    final speed = power.clamp(0.0, 1.0) * maxSpeed;
    _dirX = cos(angle);
    _dirY = sin(angle);
    _spinX = spinX.clamp(-1.0, 1.0);
    _spinY = spinY.clamp(-1.0, 1.0);
    cue.vx = _dirX * speed;
    cue.vy = _dirY * speed;
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
      b.roll(b.vx * h, b.vy * h);
      if (b.number == 0 && _spinY != 0) {
        // Sliding wears the spin off.
        _spinY *= exp(-spinDecay * sqrt(b.vx * b.vx + b.vy * b.vy) * h);
      }
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
          pocketedSound++;
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
      final inX = b.vx, inY = b.vy;
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
      final bounced = b.vx != inX || b.vy != inY;
      if (bounced) {
        final dv = max((b.vx - inX).abs(), (b.vy - inY).abs());
        cushionImpact = max(cushionImpact, dv);
      }
      if (bounced && b.number == 0 && _spinX != 0) _sideSpin(b, inX, inY);
    }
  }

  /// Side spin pushes the cue ball sideways (to the right for right spin,
  /// seen in the direction it came from) along the cushion.
  void _sideSpin(Ball b, double inX, double inY) {
    final v = sqrt(inX * inX + inY * inY);
    if (v == 0) return;
    // Right-hand side of the incoming direction (y points down).
    var kx = -inY / v * _spinX * sideFactor * v;
    var ky = inX / v * _spinX * sideFactor * v;
    // Only along the cushion.
    if (b.x <= radius || b.x >= width - radius) kx = 0;
    if (b.y <= radius || b.y >= height - radius) ky = 0;
    b.vx += kx;
    b.vy += ky;
    _spinX *= 0.6;
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
    ballImpact = max(ballImpact, rel);
    const e = 0.95;
    final impulse = rel * (1 + e) / 2;
    final cueBall = a.number == 0 ? a : (b.number == 0 ? b : null);
    final cueSpeed = cueBall == null
        ? 0.0
        : sqrt(cueBall.vx * cueBall.vx + cueBall.vy * cueBall.vy);
    a.vx -= impulse * nx;
    a.vy -= impulse * ny;
    b.vx += impulse * nx;
    b.vy += impulse * ny;
    if (cueBall != null && _spinY != 0) {
      // Follow keeps the cue ball rolling forward, draw pulls it back.
      final k = _spinY * followFactor * cueSpeed;
      cueBall.vx += _dirX * k;
      cueBall.vy += _dirY * k;
      _spinY = 0;
      _spinX *= 0.5;
    }
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
    cueInHand = true;
  }

  /// After a scratch the cue ball may be placed freely ("ball in hand").
  bool cueInHand = false;

  /// Moves the cue ball to (x, y) if it is in hand and the spot is free.
  bool placeCue(double x, double y) {
    if (!cueInHand || moving) return false;
    final px = x.clamp(radius, width - radius);
    final py = y.clamp(radius, height - radius);
    final free = balls.every(
      (b) =>
          b == cue ||
          b.pocketed ||
          pow(b.x - px, 2) + pow(b.y - py, 2) >= pow(radius * 2.05, 2),
    );
    if (!free) return false;
    cue
      ..x = px
      ..y = py;
    return true;
  }

  /// Where a shot in direction [angle] would go: the first ball the cue
  /// ball touches (ghost ball position) or the cushion it hits.
  AimPreview preview(double angle, {double spinY = 0}) {
    final dx = cos(angle), dy = sin(angle);
    var best = double.infinity;
    Ball? hit;
    for (final b in balls) {
      if (b == cue || b.pocketed) continue;
      // Distance along the ray where the cue ball touches b.
      final ox = b.x - cue.x, oy = b.y - cue.y;
      final along = ox * dx + oy * dy;
      if (along <= 0) continue;
      final perp2 = ox * ox + oy * oy - along * along;
      const r2 = 4 * radius * radius;
      if (perp2 > r2) continue;
      final t = along - sqrt(r2 - perp2);
      if (t < best) {
        best = t;
        hit = b;
      }
    }
    // Cushion distance.
    double wall = double.infinity;
    if (dx > 0) wall = min(wall, (width - radius - cue.x) / dx);
    if (dx < 0) wall = min(wall, (radius - cue.x) / dx);
    if (dy > 0) wall = min(wall, (height - radius - cue.y) / dy);
    if (dy < 0) wall = min(wall, (radius - cue.y) / dy);
    if (hit != null && best <= wall) {
      final gx = cue.x + dx * best, gy = cue.y + dy * best;
      final nx = hit.x - gx, ny = hit.y - gy;
      final len = sqrt(nx * nx + ny * ny);
      final ux = nx / len, uy = ny / len;
      // Cue ball after contact: keeps the tangential part of its motion,
      // plus follow/draw along the shot line.
      final along = dx * ux + dy * uy;
      final follow = spinY * followFactor * exp(-spinDecay * best);
      final cx = dx - along * ux + dx * follow;
      final cy = dy - along * uy + dy * follow;
      return AimPreview(gx, gy, hit, ux, uy, cueX: cx, cueY: cy);
    }
    final t = wall.isFinite ? max(0.0, wall) : 0.0;
    return AimPreview(cue.x + dx * t, cue.y + dy * t, null, 0, 0);
  }
}

/// Result of [BilliardGame.preview].
class AimPreview {
  const AimPreview(
    this.x,
    this.y,
    this.ball,
    this.dirX,
    this.dirY, {
    this.cueX = 0,
    this.cueY = 0,
  });

  /// Position of the cue ball at the moment of contact (ghost ball), or the
  /// point at the cushion.
  final double x, y;

  /// Ball that would be hit first, or null.
  final Ball? ball;

  /// Direction the hit ball will roll.
  final double dirX, dirY;

  /// Path of the cue ball after contact (length ~ relative speed).
  final double cueX, cueY;
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
  EightBallRules();

  factory EightBallRules.fromJson(Map<String, dynamic> j) {
    final r = EightBallRules()
      ..current = j['current'] as int
      ..lastEvent = j['event'] as String;
    final g = j['groups'] as List;
    for (var i = 0; i < 2; i++) {
      r.groups[i] = g[i] == null
          ? null
          : BallGroup.values.byName(g[i] as String);
    }
    return r;
  }

  Map<String, dynamic> toJson() => {
    'current': current,
    'event': lastEvent,
    'groups': [for (final g in groups) g?.name],
  };

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

  factory SoloRules.fromJson(Map<String, dynamic> j) =>
      SoloRules(SoloMode.values.byName(j['mode'] as String))
        ..penalties = j['penalties'] as int
        ..lastEvent = j['event'] as String;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'penalties': penalties,
    'event': lastEvent,
  };

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

/// A planned shot of the computer.
class PlannedShot {
  const PlannedShot(this.angle, this.power, {this.cueX, this.cueY});

  /// Where to put the cue ball first (ball in hand), or null.
  final double? cueX, cueY;
  final double angle;
  final double power;

  Map<String, dynamic> toJson() => {
    'a': angle,
    'p': power,
    if (cueX != null) 'x': cueX,
    if (cueY != null) 'y': cueY,
  };

  factory PlannedShot.fromJson(Map<String, dynamic> j) => PlannedShot(
    (j['a'] as num).toDouble(),
    (j['p'] as num).toDouble(),
    cueX: (j['x'] as num?)?.toDouble(),
    cueY: (j['y'] as num?)?.toDouble(),
  );
}

/// Computer player for 8-ball: aims every legal ball at every pocket
/// (ghost ball), tries the promising shots on a copy of the table and
/// takes the best one. [aimError] makes it human (radians of noise).
class EightBallAi {
  EightBallAi({Random? random, this.aimError = 0.006})
    : _random = random ?? Random();
  final Random _random;
  final double aimError;

  /// Plans a shot for [player] on the table [state] (see
  /// [BilliardGame.toJson]) with [rules].
  PlannedShot plan(Map<String, dynamic> state, EightBallRules rules) {
    final player = rules.current;
    final base = BilliardGame()..load(state);
    // Cue placements to consider (ball in hand: some good spots).
    final placements = <(double, double)?>[null];
    if (base.cueInHand) {
      placements
        ..clear()
        ..addAll(_placements(base, rules, player));
      if (placements.isEmpty) placements.add(null);
    }
    PlannedShot? best;
    var bestScore = -double.infinity;
    for (final place in placements) {
      final g = BilliardGame()..load(state);
      if (place != null && !g.placeCue(place.$1, place.$2)) continue;
      for (final c in _candidates(g, rules, player)) {
        final score = _try(state, rules, place, c.$1, c.$2) + c.$3;
        if (score > bestScore) {
          bestScore = score;
          best = PlannedShot(c.$1, c.$2, cueX: place?.$1, cueY: place?.$2);
        }
      }
    }
    best ??= PlannedShot(_random.nextDouble() * 2 * pi, 0.5);
    // A little human inaccuracy.
    return PlannedShot(
      best.angle + (_random.nextDouble() - 0.5) * 2 * aimError,
      (best.power * (0.97 + _random.nextDouble() * 0.06)).clamp(0.05, 1.0),
      cueX: best.cueX,
      cueY: best.cueY,
    );
  }

  /// Balls the player may aim at.
  static List<Ball> legalTargets(
    BilliardGame g,
    EightBallRules rules,
    int player,
  ) {
    final group = rules.groups[player];
    final open = [
      for (final b in g.balls)
        if (!b.pocketed && b.number != 0) b,
    ];
    if (group == null) return open.where((b) => b.number != 8).toList();
    final own = open.where((b) => groupOf(b.number) == group).toList();
    return own.isEmpty ? open.where((b) => b.number == 8).toList() : own;
  }

  /// Ghost ball shots: (angle, power, bonus for easy shots).
  List<(double, double, double)> _candidates(
    BilliardGame g,
    EightBallRules rules,
    int player,
  ) {
    const r = BilliardGame.radius;
    final out = <(double, double, double)>[];
    final cue = g.cue;
    for (final t in legalTargets(g, rules, player)) {
      for (final (px, py) in BilliardGame.pockets) {
        final tx = px - t.x, ty = py - t.y;
        final d2 = sqrt(tx * tx + ty * ty);
        if (d2 < 1e-6) continue;
        final ux = tx / d2, uy = ty / d2;
        final gx = t.x - ux * 2 * r, gy = t.y - uy * 2 * r;
        final ax = gx - cue.x, ay = gy - cue.y;
        final d1 = sqrt(ax * ax + ay * ay);
        if (d1 < 1e-6) continue;
        final cut = (ax * ux + ay * uy) / d1; // cos of the cut angle
        if (cut < 0.2) continue;
        // Something in the way of the target ball to the pocket?
        if (_blocked(g, t, t.x, t.y, px, py)) continue;
        final angle = atan2(ay, ax);
        if (g.preview(angle).ball != t) continue;
        const a = BilliardGame.friction;
        final vt = sqrt(2 * a * (d2 + 0.15));
        final vc = vt / cut;
        final v0 = sqrt(vc * vc + 2 * a * d1);
        final power = (v0 / BilliardGame.maxSpeed * 1.1).clamp(0.2, 1.0);
        out.add((angle, power, cut * 2 - d1 - d2));
      }
    }
    // Nothing to pot: touch a legal ball softly (no foul at least).
    if (out.isEmpty) {
      for (final t in legalTargets(g, rules, player)) {
        final angle = atan2(t.y - cue.y, t.x - cue.x);
        if (g.preview(angle).ball == t) out.add((angle, 0.35, -5));
      }
    }
    return out;
  }

  /// Whether another ball lies on the way from (x1, y1) to (x2, y2).
  static bool _blocked(
    BilliardGame g,
    Ball moving,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final dx = x2 - x1, dy = y2 - y1;
    final len2 = dx * dx + dy * dy;
    for (final b in g.balls) {
      if (b == moving || b == g.cue || b.pocketed) continue;
      final t = ((b.x - x1) * dx + (b.y - y1) * dy) / len2;
      if (t <= 0 || t >= 1) continue;
      final cx = x1 + dx * t - b.x, cy = y1 + dy * t - b.y;
      if (cx * cx + cy * cy < pow(BilliardGame.radius * 2.05, 2)) return true;
    }
    return false;
  }

  /// Good spots for the cue ball in hand: straight behind each legal ball
  /// on the line to each pocket.
  List<(double, double)> _placements(
    BilliardGame g,
    EightBallRules rules,
    int player,
  ) {
    final out = <(double, double)>[];
    for (final t in legalTargets(g, rules, player)) {
      for (final (px, py) in BilliardGame.pockets) {
        final dx = t.x - px, dy = t.y - py;
        final d = sqrt(dx * dx + dy * dy);
        if (d < 1e-6) continue;
        final x = t.x + dx / d * 0.3, y = t.y + dy / d * 0.3;
        if (x < 0.05 || y < 0.05 || x > 1.95 || y > 0.95) continue;
        out.add((x, y));
      }
    }
    out.shuffle(_random);
    return out.take(6).toList();
  }

  /// Plays the shot on a copy and rates the result for the shooter.
  double _try(
    Map<String, dynamic> state,
    EightBallRules rules,
    (double, double)? place,
    double angle,
    double power,
  ) {
    final g = BilliardGame()..load(state);
    if (place != null) g.placeCue(place.$1, place.$2);
    final r = EightBallRules.fromJson(rules.toJson());
    final me = r.current;
    final group = r.groups[me];
    final cleared = group != null && r.remainingOf(g, me) == 0;
    g.shoot(angle, power);
    var t = 0.0;
    while (g.moving && t < 20) {
      g.step(0.02);
      t += 0.02;
    }
    final pocketed = List<int>.from(g.pocketedThisShot)..remove(0);
    r.evaluate(
      pocketed: pocketed,
      firstHit: g.firstHit,
      scratched: g.scratched,
      clearedBefore: cleared,
    );
    if (r.isOver) return r.winner == me ? 1000 : -1000;
    var score = 0.0;
    final mine = r.groups[me];
    for (final n in pocketed) {
      score += mine != null && groupOf(n) == mine ? 10 : -3;
    }
    if (r.current == me) score += 20; // keeps the turn
    if (g.scratched || g.firstHit == null) score -= 25;
    return score;
  }
}
