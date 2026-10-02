import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/billiard/billiard_logic.dart';

void simulate(BilliardGame g) {
  for (var i = 0; i < 60 * 30 && g.moving; i++) {
    g.step(1 / 60);
  }
}

void main() {
  test('rack has 15 balls plus cue ball without overlap', () {
    final g = BilliardGame();
    expect(g.balls.length, 16);
    expect(g.balls.map((b) => b.number).toSet().length, 16);
    for (final a in g.balls) {
      for (final b in g.balls) {
        if (a == b) continue;
        expect(
          sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)),
          greaterThanOrEqualTo(BilliardGame.radius * 2),
        );
      }
    }
  });

  test('break shot moves balls, they come to rest and stay on the table', () {
    final g = BilliardGame();
    expect(g.shoot(0, 1), isTrue);
    expect(g.shoot(0, 1), isFalse, reason: 'cannot shoot while balls move');
    simulate(g);
    expect(g.moving, isFalse);
    expect(g.shots, 1);
    for (final b in g.balls.where((b) => !b.pocketed)) {
      expect(b.x, inInclusiveRange(0, BilliardGame.width));
      expect(b.y, inInclusiveRange(0, BilliardGame.height));
    }
    final fresh = BilliardGame();
    var moved = 0;
    for (var i = 1; i < 16; i++) {
      if ((g.balls[i].x - fresh.balls[i].x).abs() > 0.01) moved++;
    }
    expect(moved, greaterThan(5), reason: 'the break spreads the rack');
  });

  test('straight shot pockets a ball, cue scratch costs a penalty', () {
    final g = BilliardGame();
    for (final b in g.balls.skip(1)) {
      b.pocketed = true;
    }
    final target = g.balls[1]..pocketed = false;
    target
      ..x = BilliardGame.width - 0.2
      ..y = 0.84; // exactly on the line cue -> bottom right pocket
    g.cue
      ..x = 1.0
      ..y = 0.2;
    // Aim from the cue through the ball into the bottom right pocket.
    final angle = atan2(
      BilliardGame.height - g.cue.y,
      BilliardGame.width - g.cue.x,
    );
    g.shoot(angle, 0.8);
    simulate(g);
    expect(target.pocketed, isTrue);
    expect(g.won, isTrue);

    final s = BilliardGame();
    s.cue
      ..x = 0.2
      ..y = 0.2;
    s.shoot(atan2(-0.2, -0.2), 0.6);
    simulate(s);
    expect(s.fouls, 1);
    expect(s.cue.pocketed, isFalse, reason: 'cue ball is placed back');
    expect(s.score, 2);
  });

  eightBallTests();
  soloTests();
  controlTests();
}

void eightBallTests() {
  test('8-ball: open table assigns groups and continues the turn', () {
    final r = EightBallRules();
    r.evaluate(
      pocketed: [3],
      firstHit: 3,
      scratched: false,
      clearedBefore: false,
    );
    expect(r.groups, [BallGroup.solids, BallGroup.stripes]);
    expect(r.current, 0);
    r.evaluate(
      pocketed: [],
      firstHit: 2,
      scratched: false,
      clearedBefore: false,
    );
    expect(r.current, 1);
  });

  test('8-ball: fouls pass the turn', () {
    final r = EightBallRules()
      ..groups[0] = BallGroup.solids
      ..groups[1] = BallGroup.stripes;
    r.evaluate(
      pocketed: [2],
      firstHit: 10,
      scratched: false,
      clearedBefore: false,
    );
    expect(r.current, 1, reason: 'wrong ball first');
    r.evaluate(
      pocketed: [],
      firstHit: null,
      scratched: false,
      clearedBefore: false,
    );
    expect(r.current, 0, reason: 'nothing hit');
    r.evaluate(
      pocketed: [1],
      firstHit: 1,
      scratched: true,
      clearedBefore: false,
    );
    expect(r.current, 1, reason: 'scratch');
    expect(r.lastEvent, contains('weiße'));
  });

  test('8-ball: the black ball decides', () {
    final early = EightBallRules()
      ..groups[0] = BallGroup.solids
      ..groups[1] = BallGroup.stripes;
    early.evaluate(
      pocketed: [8],
      firstHit: 1,
      scratched: false,
      clearedBefore: false,
    );
    expect(early.winner, 1);

    final legal = EightBallRules()
      ..groups[0] = BallGroup.solids
      ..groups[1] = BallGroup.stripes;
    legal.evaluate(
      pocketed: [8],
      firstHit: 8,
      scratched: false,
      clearedBefore: true,
    );
    expect(legal.winner, 0);

    final scratch = EightBallRules()
      ..groups[0] = BallGroup.solids
      ..groups[1] = BallGroup.stripes;
    scratch.evaluate(
      pocketed: [8],
      firstHit: 8,
      scratched: true,
      clearedBefore: true,
    );
    expect(scratch.winner, 1);
  });

  test('first hit, snapshot and restore', () {
    final g = BilliardGame();
    g.shoot(0, 0.8);
    simulate(g);
    expect(g.firstHit, isNotNull);
    final snap = g.snapshot();
    final other = BilliardGame()..restore(snap);
    for (var i = 0; i < 16; i++) {
      expect(other.balls[i].x, g.balls[i].x);
      expect(other.balls[i].pocketed, g.balls[i].pocketed);
    }
  });
}

void soloTests() {
  test('solo 8 last: early black ball loses, last black ball wins', () {
    final early = SoloRules(SoloMode.eightLast);
    early.evaluate(
      pocketed: [8, 3],
      firstHit: 3,
      scratched: false,
      othersBefore: 5,
      targetBefore: null,
    );
    expect(early.lost, isTrue);

    final legal = SoloRules(SoloMode.eightLast);
    legal.evaluate(
      pocketed: [8],
      firstHit: 8,
      scratched: false,
      othersBefore: 0,
      targetBefore: null,
    );
    expect(legal.lost, isFalse);
    expect(legal.penalties, 0);

    final touchEight = SoloRules(SoloMode.eightLast);
    touchEight.evaluate(
      pocketed: [],
      firstHit: 8,
      scratched: false,
      othersBefore: 3,
      targetBefore: null,
    );
    expect(touchEight.penalties, 1);
  });

  test('solo rotation: lowest ball first', () {
    final g = BilliardGame();
    final r = SoloRules(SoloMode.rotation);
    expect(r.target(g), 1);
    g.balls.firstWhere((b) => b.number == 1).pocketed = true;
    expect(r.target(g), 2);
    r.evaluate(
      pocketed: [5],
      firstHit: 5,
      scratched: false,
      othersBefore: 13,
      targetBefore: 2,
    );
    expect(r.penalties, 1);
    r.evaluate(
      pocketed: [],
      firstHit: 2,
      scratched: false,
      othersBefore: 13,
      targetBefore: 2,
    );
    expect(r.penalties, 1);
    expect(SoloRules.othersLeft(g), 13);
  });
}

void controlTests() {
  test('aim preview finds the ghost ball and the object ball direction', () {
    final g = BilliardGame();
    for (final b in g.balls.skip(1)) {
      b.pocketed = true;
    }
    final target = g.balls[1]..pocketed = false;
    target
      ..x = 1.0
      ..y = 0.5;
    g.cue
      ..x = 0.5
      ..y = 0.5;
    final p = g.preview(0);
    expect(p.ball, target);
    expect(p.x, closeTo(1.0 - BilliardGame.radius * 2, 1e-9));
    expect(p.dirX, closeTo(1, 1e-9));
    final miss = g.preview(pi / 2);
    expect(miss.ball, isNull);
    expect(miss.y, closeTo(BilliardGame.height - BilliardGame.radius, 1e-9));
  });

  test('ball in hand after a scratch', () {
    final g = BilliardGame();
    expect(g.cueInHand, isTrue, reason: 'free placement for the break');
    expect(g.placeCue(0.3, 0.3), isTrue);
    g.shoot(0, 0.01);
    simulate(g);
    expect(g.placeCue(0.3, 0.4), isFalse, reason: 'no longer in hand');
    g.cue
      ..x = 0.1
      ..y = 0.1;
    g.shoot(atan2(-0.1, -0.1), 0.5);
    simulate(g);
    expect(g.cueInHand, isTrue);
    expect(g.placeCue(0.4, 0.2), isTrue);
    expect((g.cue.x, g.cue.y), (0.4, 0.2));
    final rackBall = g.balls[5];
    expect(g.placeCue(rackBall.x, rackBall.y), isFalse, reason: 'occupied');
    g.shoot(0, 0.3);
    expect(g.cueInHand, isFalse);
  });

  group('spin', () {
    /// Cue ball at x=0.5, one object ball straight ahead at x=1.0.
    BilliardGame straight() {
      final g = BilliardGame();
      for (final b in g.balls.skip(1)) {
        b.pocketed = true;
      }
      g.balls[1]
        ..pocketed = false
        ..x = 1.0
        ..y = 0.5;
      g.cue
        ..x = 0.5
        ..y = 0.5;
      return g;
    }

    /// Cue ball speed along the shot line right after the contact.
    double cueAfter(double spinY) {
      final g = straight();
      g.shoot(0, 0.5, spinY: spinY);
      for (var i = 0; i < 600 && g.firstHit == null; i++) {
        g.step(1 / 600);
      }
      expect(g.firstHit, 1);
      return g.cue.vx;
    }

    test('stun stops, follow runs on, draw comes back', () {
      final stun = cueAfter(0);
      final follow = cueAfter(0.7);
      final draw = cueAfter(-0.7);
      expect(stun.abs(), lessThan(0.1));
      expect(follow, greaterThan(0.5));
      expect(draw, lessThan(-0.5));
    });

    test('preview shows the cue ball path with spin', () {
      final g = straight();
      expect(g.preview(0).cueX.abs(), lessThan(0.01));
      expect(g.preview(0, spinY: 0.7).cueX, greaterThan(0.2));
      expect(g.preview(0, spinY: -0.7).cueX, lessThan(-0.2));
    });

    test('side spin bends the rebound off a cushion', () {
      double yAfterBounce(double spinX) {
        final g = straight();
        g.balls[1]
          ..x = 0.2
          ..y = 0.1;
        g.cue
          ..x = 1.0
          ..y = 0.5;
        g.shoot(0, 0.4, spinX: spinX);
        for (var i = 0; i < 60 && g.cue.vx >= 0; i++) {
          g.step(1 / 60);
        }
        return g.cue.vy;
      }

      expect(yAfterBounce(0), closeTo(0, 1e-9));
      // Moving right, right spin pushes down (to the right of the path).
      expect(yAfterBounce(0.7), greaterThan(0.05));
      expect(yAfterBounce(-0.7), lessThan(-0.05));
    });
  });

  test('balls roll: the top turns forward, a full turn returns', () {
    final b = Ball(3, 0.5, 0.5);
    const r = BilliardGame.radius;
    b.roll(pi / 2 * r, 0);
    expect(b.orientation.qx, closeTo(1, 1e-9));
    expect(b.orientation.qz, closeTo(0, 1e-9));
    b.roll(pi / 2 * r, 0);
    b.roll(pi * r, 0);
    expect(b.orientation.qz, closeTo(1, 1e-9));
    b.roll(0, pi / 2 * r);
    expect(b.orientation.qy, closeTo(1, 1e-9));
    // Stays a unit vector perpendicular to the stripe axis.
    expect(
      b.orientation.qx * b.orientation.ax +
          b.orientation.qy * b.orientation.ay +
          b.orientation.qz * b.orientation.az,
      closeTo(0, 1e-9),
    );
  });
}
