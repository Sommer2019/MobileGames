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
