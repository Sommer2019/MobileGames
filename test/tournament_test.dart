import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/tournament/tournament_logic.dart';

void main() {
  test('schedule repeats the games for every round', () {
    final t = Tournament(games: ['chess', 'mill'], rounds: 3, players: 2);
    expect(t.schedule, ['chess', 'mill', 'chess', 'mill', 'chess', 'mill']);
    expect(t.matchCount, 6);
    expect(t.nextMatch, 0);
  });

  test('points: win 3, draw 1, duplicates ignored, ranking', () {
    final t = Tournament(games: ['connect_four'], rounds: 3, players: 3);
    t.record(0, [2]);
    t.record(0, [1]); // duplicate report is ignored
    t.record(1, [0, 1, 2]); // draw
    expect(t.points, [1, 1, 4]);
    expect(t.nextMatch, 2);
    t.record(2, [0]);
    expect(t.finished, isTrue);
    expect(t.points, [4, 1, 4]);
    expect(t.ranking().last, 1);
    expect(t.leaders().toSet(), {0, 2});
  });
}
