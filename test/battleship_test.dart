import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/battleship/battleship_logic.dart';

void main() {
  test('random fleet is complete and ships never touch', () {
    for (var seed = 0; seed < 50; seed++) {
      final b = FleetBoard.random(Random(seed));
      expect(b.ships.map((s) => s.cells.length).toList(), fleetSizes);
      for (final a in b.ships) {
        for (final o in b.ships) {
          if (a == o) continue;
          for (final (x1, y1) in a.cells) {
            for (final (x2, y2) in o.cells) {
              expect(max((x1 - x2).abs(), (y1 - y2).abs()), greaterThan(1));
            }
          }
        }
      }
    }
  });

  test('placement rules', () {
    final b = FleetBoard();
    expect(b.place(0, 0, 5, true), isTrue);
    expect(b.place(0, 1, 3, true), isFalse, reason: 'touching');
    expect(b.place(7, 0, 4, true), isFalse, reason: 'out of bounds');
    expect(b.place(0, 2, 3, true), isTrue);
  });

  test('shots: miss, hit, sunk, fleet destroyed (serialised like online)', () {
    final b = FleetBoard()..place(0, 0, 2, false);
    final target = TargetBoard();
    ShotOutcome shoot(int x, int y) {
      final o = ShotOutcome.fromJson(b.receiveShot(x, y).toJson());
      target.apply(x, y, o);
      return o;
    }

    expect(shoot(5, 5).result, ShotResult.miss);
    expect(shoot(0, 0).result, ShotResult.hit);
    final last = shoot(0, 1);
    expect(last.result, ShotResult.sunk);
    expect(last.sunkCells.toSet(), {(0, 0), (0, 1)});
    expect(last.fleetDestroyed, isTrue);
    expect(target.cells[1][0], TargetCell.sunk);
    // Neighbours of a sunk ship are marked as water.
    expect(target.cells[2][0], TargetCell.miss);
    expect(target.cells[0][1], TargetCell.miss);
  });

  test('AI sinks a full random fleet in at most 100 shots', () {
    for (var seed = 0; seed < 20; seed++) {
      final board = FleetBoard.random(Random(seed));
      final ai = BattleshipAi(Random(seed + 100));
      var shots = 0;
      while (!board.allSunk) {
        final (x, y) = ai.nextShot();
        expect(
          ai.knowledge.canShoot(x, y),
          isTrue,
          reason: 'never shoots twice',
        );
        ai.learn(x, y, board.receiveShot(x, y));
        shots++;
      }
      expect(shots, lessThanOrEqualTo(100));
    }
  });
}
