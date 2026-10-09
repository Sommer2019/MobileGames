import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/billiard/billiard_logic.dart';

/// Plays one shot to the end, like the screen does.
void play(BilliardGame g, EightBallRules r, PlannedShot s) {
  if (s.cueX != null) g.placeCue(s.cueX!, s.cueY!);
  final group = r.groups[r.current];
  final cleared = group != null && r.remainingOf(g, r.current) == 0;
  g.shoot(s.angle, s.power);
  var t = 0.0;
  while (g.moving && t < 30) {
    g.step(0.02);
    t += 0.02;
  }
  r.evaluate(
    pocketed: List<int>.from(g.pocketedThisShot)..remove(0),
    firstHit: g.firstHit,
    scratched: g.scratched,
    clearedBefore: cleared,
  );
}

void main() {
  test('the computer pots balls and finishes games', () {
    var games = 0, shots = 0, pots = 0;
    final sw = Stopwatch()..start();
    for (var seed = 0; seed < 4; seed++) {
      final g = BilliardGame();
      final r = EightBallRules();
      final ai = EightBallAi(random: Random(seed));
      var n = 0;
      while (!r.isOver && n < 120) {
        final before = g.remaining;
        play(g, r, ai.plan(g.toJson(), r));
        pots += before - g.remaining;
        n++;
      }
      shots += n;
      if (r.isOver) games++;
    }
    final perShot = sw.elapsedMilliseconds / shots;
    // ignore: avoid_print
    print(
      'finished $games/4, $shots shots, $pots pots, ${perShot.round()} ms/shot',
    );
    expect(games, 4);
    expect(pots / shots, greaterThan(0.4));
  });
}
