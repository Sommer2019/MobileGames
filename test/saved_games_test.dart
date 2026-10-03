import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/saved_games.dart';
import 'package:mobile_games/games/battleship/battleship_logic.dart';
import 'package:mobile_games/games/billiard/billiard_logic.dart';
import 'package:mobile_games/games/checkers/checkers_logic.dart';
import 'package:mobile_games/games/chess/chess_logic.dart';
import 'package:mobile_games/games/connect_four/connect_four_logic.dart';
import 'package:mobile_games/games/connect_four/connect_four_screen.dart';
import 'package:mobile_games/games/darts/darts_logic.dart';
import 'package:mobile_games/games/mahjong/mahjong_logic.dart';
import 'package:mobile_games/games/mill/mill_logic.dart';
import 'package:mobile_games/games/snake/snake_logic.dart';
import 'package:mobile_games/games/solitaire/klondike_logic.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_logic.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round trip through JSON text, as stored on the device.
Map<String, dynamic> viaText(Object data) =>
    jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

void main() {
  group('logic round trips', () {
    test('chess replays the moves', () {
      final g = ChessGame()
        ..move('e2', 'e4')
        ..move('e7', 'e5')
        ..move('g1', 'f3');
      final copy = ChessGame.fromMoves(viaText({'m': g.moveList})['m'] as List);
      expect(copy.fen, g.fen);
      expect(copy.lastMove, ('g1', 'f3'));
    });

    test('checkers replays the moves', () {
      final g = CheckersGame()..playPath(const [(5, 0), (4, 1)]);
      final copy = CheckersGame.replay(viaText({'m': g.history})['m'] as List);
      expect(copy.turn, Side.black);
      expect(copy.board[4][1]?.side, Side.white);
      expect(copy.board[5][0], isNull);
    });

    test('mill keeps board and stones to place', () {
      final g = MillGame()
        ..place(0)
        ..place(9);
      final copy = MillGame.fromJson(viaText(g.toJson()));
      expect(copy.board, g.board);
      expect(copy.toPlace, g.toPlace);
      expect(copy.turn, g.turn);
      expect(copy.isFresh, isFalse);
    });

    test('connect four replays the columns', () {
      final g = ConnectFourGame()
        ..drop(3)
        ..drop(4);
      final copy = ConnectFourGame.replay(2, [...g.moves]);
      expect(copy.board, g.board);
      expect(copy.currentPlayer, 1);
    });

    test('kniffel keeps sheets and dice', () {
      final g = KniffelGame(2, random: Random(1))..roll();
      g.score(KniffelCategory.chance);
      g.roll();
      g.toggleHold(2);
      final copy = KniffelGame.fromJson(viaText(g.toJson()));
      expect(copy.sheets[0].total, g.sheets[0].total);
      expect(copy.dice, g.dice);
      expect(copy.held, g.held);
      expect(copy.rollsLeft, g.rollsLeft);
      expect(copy.currentPlayer, 1);
    });

    test('klondike keeps every card', () {
      final g = KlondikeGame(drawCount: 3, random: Random(4))..score = 42;
      final copy = KlondikeGame.fromJson(viaText(g.toJson()));
      expect(copy.toJson(), g.toJson());
      expect(copy.drawCount, 3);
      expect(copy.tableau[6].last.faceUp, isTrue);
      expect(copy.tableau[6].first.faceUp, isFalse);
    });

    test('mahjong keeps faces and removed tiles', () {
      final g = MahjongGame.generate(layout: towerLayout(), random: Random(2));
      final (a, b) = g.hint()!;
      g.match(a, b);
      final copy = MahjongGame.fromJson(towerLayout(), viaText(g.toJson()));
      expect(copy.remaining, g.remaining);
      expect(copy.history.single.$1.id, a.id);
      expect(
        [for (final t in copy.tiles) t.face],
        [for (final t in g.tiles) t.face],
      );
      expect(copy.undo(), isTrue);
      expect(copy.remaining, g.tiles.length);
    });

    test('billiard keeps the balls and the rules', () {
      final g = BilliardGame()..rack();
      g.balls[3].pocketed = true;
      g.balls[0].x = 0.4;
      g.shots = 5;
      final copy = BilliardGame()..load(viaText(g.toJson()));
      expect(copy.remaining, 14);
      expect(copy.cue.x, 0.4);
      expect(copy.shots, 5);
      final rules = SoloRules(SoloMode.rotation)..penalties = 2;
      final r2 = SoloRules.fromJson(viaText(rules.toJson()));
      expect(r2.mode, SoloMode.rotation);
      expect(r2.penalties, 2);
      final eight = EightBallRules()
        ..current = 1
        ..groups[0] = BallGroup.stripes
        ..groups[1] = BallGroup.solids;
      final e2 = EightBallRules.fromJson(viaText(eight.toJson()));
      expect(e2.current, 1);
      expect(e2.groups, [BallGroup.stripes, BallGroup.solids]);
    });

    test('darts keeps scores and the running turn', () {
      final g = DartsGame(players: 2, mode: DartsMode.x301)
        ..throwDart(const DartHit(20, 3))
        ..throwDart(const DartHit(5, 1));
      final copy = DartsGame.fromJson(viaText(g.toJson()));
      expect(copy.states[0].remaining, 301 - 65);
      expect(copy.dartsInTurn, 2);
      copy.throwDart(const DartHit(1, 1));
      expect(copy.current, 1);
    });

    test('snake keeps body, food and score', () {
      final g = SnakeGame(wrap: true, random: Random(3))
        ..step()
        ..turn(Dir.left);
      g.score = 7;
      final copy = SnakeGame.fromJson(viaText(g.toJson()));
      expect(copy.body, g.body);
      expect(copy.food, g.food);
      expect(copy.score, 7);
      expect(copy.direction, Dir.left);
      expect(copy.wrap, isTrue);
    });

    test('battleship keeps fleets and knowledge', () {
      final fleet = FleetBoard.random(Random(5));
      final (x, y) = fleet.ships.first.cells.first;
      final o = fleet.receiveShot(x, y);
      final target = TargetBoard()..apply(x, y, o);
      final copy = FleetBoard.fromJson(viaText(fleet.toJson()));
      expect(copy.ships.length, fleet.ships.length);
      expect(copy.ships.first.hits, {(x, y)});
      expect(copy.shotsReceived, {(x, y)});
      final t2 = TargetBoard()..load(viaText({'t': target.toJson()})['t']);
      expect(t2.cells[y][x], TargetCell.hit);
    });
  });

  group('screens', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SavedGames.load();
    });
    tearDown(SavedGames.reset);

    Widget app(Widget child) => MaterialApp(home: child);
    const setup = PlaySetup.local();

    testWidgets('a round is continued after leaving', (tester) async {
      await tester.pumpWidget(app(const ConnectFourScreen(setup: setup)));
      await tester.tap(find.byKey(const ValueKey('c4col3')));
      await tester.pump();
      expect(find.text('Gelb ist am Zug'), findsOneWidget);

      // Leave the game.
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pump();
      expect(SavedGames.read('connect_four.local2'), {
        'round': 0,
        'moves': [3],
      });

      await tester.pumpWidget(app(const ConnectFourScreen(setup: setup)));
      await tester.pump();
      expect(find.text('Gelb ist am Zug'), findsOneWidget);
      expect(find.text('Spielstand fortgesetzt'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('restart asks and starts over', (tester) async {
      await tester.pumpWidget(app(const ConnectFourScreen(setup: setup)));
      await tester.tap(find.byKey(const ValueKey('c4col3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('restart')));
      await tester.pumpAndSettle();
      expect(find.text('Neu starten?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('restartConfirm')));
      await tester.pumpAndSettle();
      expect(find.text('Rot ist am Zug'), findsOneWidget);

      await tester.pumpWidget(app(const SizedBox()));
      await tester.pump();
      expect(SavedGames.read('connect_four.local2'), isNull);
    });

    testWidgets('a broken save is ignored', (tester) async {
      SavedGames.write('connect_four.local2', {'moves': 'kaputt'});
      await tester.pump();
      await tester.pumpWidget(app(const ConnectFourScreen(setup: setup)));
      expect(find.text('Rot ist am Zug'), findsOneWidget);
    });

    testWidgets('one save per mode', (tester) async {
      expect(setup.saveKey('chess'), 'chess.local2');
      expect(const PlaySetup.ai().saveKey('chess'), 'chess.ai2');
    });
  });
}
