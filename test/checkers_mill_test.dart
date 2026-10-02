import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/checkers/checkers_logic.dart';
import 'package:mobile_games/games/mill/mill_logic.dart';

CheckersGame emptyBoard() {
  final g = CheckersGame();
  for (final row in g.board) {
    row.fillRange(0, 8, null);
  }
  return g;
}

void main() {
  group('Dame', () {
    test('start position: 12 stones each, white has 7 moves', () {
      final g = CheckersGame();
      expect(g.count(Side.white), 12);
      expect(g.count(Side.black), 12);
      expect(g.turn, Side.white);
      expect(g.legalMoves().length, 7);
    });

    test('capturing is mandatory; men capture backwards only if enabled', () {
      final g = emptyBoard();
      g.board[4][3] = const Piece(Side.white);
      g.board[3][4] = const Piece(Side.black); // forward capture possible
      g.board[7][0] = const Piece(Side.white);
      final moves = g.legalMoves();
      expect(moves.every((m) => m.isCapture), isTrue);
      expect(moves.single.to, (2, 5));

      final b = emptyBoard();
      b.board[3][4] = const Piece(Side.white);
      b.board[4][5] = const Piece(Side.black); // behind the white man
      b.board[0][1] = const Piece(Side.black);
      expect(b.legalMoves().any((m) => m.isCapture), isFalse);

      final intl = CheckersGame(menCaptureBackwards: true);
      for (final row in intl.board) {
        row.fillRange(0, 8, null);
      }
      intl.board[3][4] = const Piece(Side.white);
      intl.board[4][5] = const Piece(Side.black);
      intl.board[0][1] = const Piece(Side.black);
      expect(intl.legalMoves().single.to, (5, 6));
    });

    test('multi capture is one move and removes all victims', () {
      final g = emptyBoard();
      g.board[6][1] = const Piece(Side.white);
      g.board[5][2] = const Piece(Side.black);
      g.board[3][4] = const Piece(Side.black);
      g.board[0][7] = const Piece(Side.black);
      final m = g.legalMoves().single;
      expect(m.path, [(6, 1), (4, 3), (2, 5)]);
      expect(g.playPath(m.path), isTrue);
      expect(g.count(Side.black), 1);
      expect(g.turn, Side.black);
    });

    test('promotion and flying king', () {
      final g = emptyBoard();
      g.board[1][2] = const Piece(Side.white);
      g.board[2][7] = const Piece(Side.black);
      expect(g.playPath([(1, 2), (0, 1)]), isTrue);
      expect(g.board[0][1]!.king, isTrue);
      g.turn = Side.white;
      final targets = g.legalMoves().map((m) => m.to).toSet();
      expect(targets, containsAll([(1, 0), (1, 2), (3, 4), (6, 7)]));
      // Flying capture over a distance.
      final k = emptyBoard();
      k.board[7][0] = const Piece(Side.white, king: true);
      k.board[3][4] = const Piece(Side.black);
      final caps = k.legalMoves();
      expect(caps.every((m) => m.isCapture), isTrue);
      expect(caps.map((m) => m.to).toSet(), {(2, 5), (1, 6), (0, 7)});
    });

    test('no stones or no moves loses', () {
      final g = emptyBoard();
      g.board[4][3] = const Piece(Side.white);
      g.board[3][4] = const Piece(Side.black);
      expect(g.playPath([(4, 3), (2, 5)]), isTrue);
      expect(g.winner, Side.white);
    });

    test('random AI games always finish with legal moves', () {
      for (var seed = 0; seed < 5; seed++) {
        final g = CheckersGame();
        final r = Random(seed);
        var moves = 0;
        while (!g.isOver && moves < 400) {
          final m = g.aiMove(r)!;
          expect(g.playPath(m.path), isTrue);
          moves++;
        }
        expect(g.isOver || moves == 400, isTrue);
      }
    });
  });

  group('Mühle', () {
    test('board geometry', () {
      expect(MillGame.mills.length, 16);
      expect(MillGame.neighbours.expand((n) => n).length, 64); // 32 edges
      expect(MillGame.neighbours[9].toSet(), {8, 10, 1, 17});
    });

    test('placing a mill lets you remove a stone not in a mill', () {
      final g = MillGame();
      g.place(0); // W
      g.place(8); // B
      g.place(1); // W
      g.place(9); // B
      expect(g.place(2), isTrue); // W closes mill 0-1-2
      expect(g.mustRemove, isTrue);
      expect(g.turn, 1);
      expect(g.place(3), isFalse, reason: 'must remove first');
      expect(g.remove(0), isFalse, reason: 'own stone');
      expect(g.remove(8), isTrue);
      expect(g.turn, 2);
      expect(g.stones(2), 1);
    });

    test('stones in a mill are protected unless all are in mills', () {
      final g = MillGame();
      for (final p in [8, 0, 9, 1, 10]) {
        g.place(p); // black closes 8-9-10 on its 3rd stone
      }
      expect(g.mustRemove, isTrue);
      expect(g.removable().toSet(), {0, 1});
    });

    test('moving phase, flying with three stones and losing', () {
      final g = MillGame();
      g.toPlace
        ..[1] = 0
        ..[2] = 0;
      for (final p in [0, 1, 4]) {
        g.board[p] = 1;
      }
      for (final p in [8, 9, 12, 20, 22]) {
        g.board[p] = 2;
      }
      expect(g.canFly(1), isTrue);
      expect(g.targets(4).length, 24 - 8);
      expect(g.move(4, 2), isTrue); // flies and closes 0-1-2
      expect(g.mustRemove, isTrue);
      g.remove(20);
      expect(g.turn, 2);
      expect(g.canFly(2), isFalse);
      expect(g.targets(8).toSet(), {15});
      expect(g.move(8, 15), isTrue);
      // Re-opening and closing a mill counts again.
      expect(g.move(2, 3), isTrue);
      expect(g.move(15, 8), isTrue);
      expect(g.move(3, 2), isTrue);
      expect(g.mustRemove, isTrue);
      g.remove(12);
      expect(g.stones(2), 3);
      expect(g.canFly(2), isTrue);
      expect(g.winner, 0);
    });

    test('dropping below three stones loses', () {
      final g = MillGame();
      g.toPlace
        ..[1] = 0
        ..[2] = 0;
      for (final p in [0, 1, 3]) {
        g.board[p] = 1;
      }
      for (final p in [12, 13, 14]) {
        g.board[p] = 2;
      }
      expect(g.move(3, 2), isTrue);
      expect(g.remove(12), isTrue);
      expect(g.winner, 1);
      expect(g.isOver, isTrue);
    });

    test('AI plays complete legal games', () {
      for (var seed = 0; seed < 5; seed++) {
        final g = MillGame();
        final r = Random(seed);
        var n = 0;
        while (!g.isOver && n < 500) {
          final a = g.aiAction(r)!;
          final ok = switch (a.$1) {
            'place' => g.place(a.$2),
            'move' => g.move(a.$2, a.$3),
            _ => g.remove(a.$2),
          };
          expect(ok, isTrue, reason: '$a');
          n++;
        }
      }
    });
  });
}
