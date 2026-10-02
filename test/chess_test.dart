import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/chess/chess_logic.dart';

void main() {
  test('opening moves and turn', () {
    final g = ChessGame();
    expect(g.pieceAt('e1'), 'K');
    expect(g.pieceAt('e8'), 'k');
    expect(g.targets('e2').toSet(), {'e3', 'e4'});
    expect(g.targets('g1').toSet(), {'f3', 'h3'});
    expect(g.move('e2', 'e5'), isFalse);
    expect(g.move('e2', 'e4'), isTrue);
    expect(g.turn, ChessSide.black);
    expect(g.move('d2', 'd4'), isFalse, reason: 'not white\'s turn');
  });

  test('fool\'s mate', () {
    final g = ChessGame();
    g.move('f2', 'f3');
    g.move('e7', 'e5');
    g.move('g2', 'g4');
    g.move('d8', 'h4');
    expect(g.isCheckmate, isTrue);
    expect(g.isOver, isTrue);
    expect(g.statusText(), contains('Schwarz gewinnt'));
  });

  test('AI always returns a legal move and finds mate in one', () {
    final g = ChessGame();
    final rnd = Random(5);
    for (var i = 0; i < 20 && !g.isOver; i++) {
      final m = g.aiMove(rnd)!;
      expect(g.move(m.$1, m.$2, promotion: m.$3), isTrue);
    }
    final mate = ChessGame();
    mate.move('f2', 'f3');
    mate.move('e7', 'e5');
    mate.move('g2', 'g4');
    final m = mate.aiMove(rnd)!;
    expect((m.$1, m.$2), ('d8', 'h4'));
  });
}
