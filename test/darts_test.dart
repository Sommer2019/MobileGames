import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/darts/darts_logic.dart';

DartHit hit(int v, [int m = 1]) => DartHit(v, m);

void main() {
  test('board scoring', () {
    expect(Board.score(0, 0).label, 'Bull');
    expect(Board.score(10, 0).label, '25');
    expect(Board.score(0, -103).label, 'T20');
    expect(Board.score(0, -166).label, 'D20');
    expect(Board.score(0, -60).label, 'S20');
    expect(Board.score(0, 60).label, 'S3');
    expect(Board.score(60, 0).label, 'S6');
    expect(Board.score(-60, 0).label, 'S11');
    expect(Board.score(0, -175).isMiss, isTrue);
    for (final n in Board.numbers) {
      for (final m in [1, 2, 3]) {
        final (x, y) = Board.aimPoint(n, multiplier: m);
        final h = Board.score(x, y);
        expect((h.value, h.multiplier), (n, m));
      }
    }
  });

  test('501 double out: checkout and bust rules', () {
    final g = DartsGame(players: 2, mode: DartsMode.x501);
    g.throwDart(hit(20, 3));
    g.throwDart(hit(20, 3));
    g.throwDart(hit(20, 3));
    expect(g.states[0].remaining, 321);
    expect(g.current, 1);
    expect(g.states[0].average, 180);

    final c = DartsGame(players: 1, mode: DartsMode.x301);
    c.states[0].remaining = 40;
    c.throwDart(hit(20)); // 20 left
    c.throwDart(hit(20)); // 0 but not double -> bust
    expect(c.lastTurnBust, isTrue);
    expect(c.states[0].remaining, 40);
    expect(c.dartsInTurn, 0);
    c.throwDart(hit(19)); // 21
    c.throwDart(hit(20)); // 1 -> bust with double out
    expect(c.states[0].remaining, 40);
    c.throwDart(hit(20, 2));
    expect(c.winner, 0);
    expect(c.isOver, isTrue);
  });

  test('single out allows finishing with any dart', () {
    final g = DartsGame(players: 1, mode: DartsMode.x301, doubleOut: false);
    g.states[0].remaining = 7;
    g.throwDart(hit(7));
    expect(g.winner, 0);
  });

  test('around the clock', () {
    final g = DartsGame(players: 2, mode: DartsMode.aroundTheClock);
    expect(g.targetOf(0), 1);
    g.throwDart(hit(1, 3));
    g.throwDart(hit(5));
    g.throwDart(hit(2, 2));
    expect(g.targetOf(0), 3);
    expect(g.current, 1);
    g.states[1].remaining = 20; // needs bull
    g.throwDart(hit(25));
    expect(g.winner, 1);
  });

  test('turns rotate through up to four players and count rounds', () {
    final g = DartsGame(players: 4, mode: DartsMode.x501);
    for (var i = 0; i < 12; i++) {
      g.throwDart(hit(1));
    }
    expect(g.current, 0);
    expect(g.round, 2);
    expect(g.states.every((s) => s.remaining == 498), isTrue);
  });
}
