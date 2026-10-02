import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/connect_four/connect_four_logic.dart';

void main() {
  test('vertical win', () {
    final g = ConnectFourGame();
    for (var i = 0; i < 3; i++) {
      g.drop(0);
      g.drop(1);
    }
    expect(g.winner, 0);
    g.drop(0);
    expect(g.winner, 1);
    expect(g.winningCells.length, 4);
    expect(g.canDrop(2), isFalse, reason: 'no moves after game over');
  });

  test('diagonal win', () {
    final g = ConnectFourGame();
    for (final c in [0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3]) {
      g.drop(c);
    }
    expect(g.winner, 1);
    expect(g.winningCells.toSet(), {(5, 0), (4, 1), (3, 2), (2, 3)});
  });

  test('full column rejects drops and draw is detected', () {
    final g = ConnectFourGame();
    for (var i = 0; i < 6; i++) {
      expect(g.drop(0), 5 - i);
    }
    expect(g.drop(0), -1);

    final d = ConnectFourGame();
    const seq = [
      0,
      1,
      5,
      5,
      0,
      2,
      3,
      2,
      0,
      3,
      4,
      5,
      3,
      6,
      4,
      3,
      5,
      6,
      2,
      2,
      2,
      2,
      3,
      0,
      4,
      1,
      6,
      1,
      0,
      4,
      5,
      0,
      1,
      1,
      1,
      4,
      4,
      3,
      5,
      6,
      6,
      6,
    ];
    for (final c in seq) {
      expect(d.drop(c), isNot(-1));
    }
    expect(d.winner, 0);
    expect(d.draw, isTrue);
  });

  test('AI takes an immediate win and blocks a threat', () {
    final g = ConnectFourGame();
    // Player 1 has three in column 3; player 2 (AI) must block.
    g.drop(3);
    g.drop(0);
    g.drop(3);
    g.drop(0);
    g.drop(3);
    expect(ConnectFourAi(depth: 4).bestMove(g), 3);

    final w = ConnectFourGame();
    w.drop(1);
    w.drop(6);
    w.drop(2);
    w.drop(6);
    w.drop(3);
    w.drop(5); // player two, now player one can win at 0 or 4
    final move = ConnectFourAi(depth: 4).bestMove(w);
    expect([0, 4], contains(move));
  });

  test('four players: bigger board, turns rotate through all players', () {
    final g = ConnectFourGame(players: 4);
    expect((g.columns, g.rows), (10, 8));
    expect(g.currentPlayer, 1);
    g.drop(0);
    expect(g.currentPlayer, 2);
    g.drop(1);
    g.drop(2);
    expect(g.currentPlayer, 4);
    g.drop(3);
    expect(g.currentPlayer, 1);
    expect(g.board[7].sublist(0, 4), [1, 2, 3, 4]);
  });

  test('three players: player three can win', () {
    final g = ConnectFourGame(players: 3);
    expect((g.columns, g.rows), (9, 7));
    for (var i = 0; i < 3; i++) {
      g.drop(0);
      g.drop(1);
      g.drop(8);
    }
    g.drop(0); // player 1 wins vertically
    expect(g.winner, 1);
    final h = ConnectFourGame(players: 3);
    for (var i = 0; i < 4; i++) {
      h.drop(2 * i);
      h.drop(2 * i + 1);
      if (h.isOver) break;
      h.drop(8);
    }
    expect(h.winner, 3);
  });
}
