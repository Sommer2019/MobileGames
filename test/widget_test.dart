import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/billiard/billiard_screen.dart';
import 'package:mobile_games/games/checkers/checkers_screen.dart';
import 'package:mobile_games/games/chess/chess_screen.dart';
import 'package:mobile_games/games/mill/mill_screen.dart';
import 'package:mobile_games/games/darts/darts_screen.dart';
import 'package:mobile_games/games/billiard/eight_ball_screen.dart';
import 'package:mobile_games/games/connect_four/connect_four_screen.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_screen.dart';
import 'package:mobile_games/games/mahjong/mahjong_screen.dart';
import 'package:mobile_games/games/battleship/battleship_local_screen.dart';
import 'package:mobile_games/games/battleship/battleship_screen.dart';
import 'package:mobile_games/games/snake/snake_screen.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_screen.dart';
import 'package:mobile_games/ui/home_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

Widget app(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home lists all games', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HomeScreen()));
    expect(find.text('Turnier mit Freunden'), findsOneWidget);
    final titles = [
      'Schach',
      'Schiffe versenken',
      '4 gewinnt',
      'Dame',
      'Mühle',
      'Kniffel',
      'Darts',
      'Billard',
      'Kugellabyrinth',
      'Mahjong',
      'Snake',
    ];
    for (final t in titles) {
      expect(find.text(t), findsWidgets);
    }
  });

  testWidgets('connect four hot seat until a win', (tester) async {
    await tester.pumpWidget(
      app(const ConnectFourScreen(setup: PlaySetup.local())),
    );
    expect(find.text('Rot ist am Zug'), findsOneWidget);
    for (final c in [0, 1, 0, 1, 0, 1, 0]) {
      await tester.tap(find.byKey(ValueKey('c4col$c')));
      await tester.pump();
    }
    expect(find.text('Rot gewinnt!'), findsOneWidget);
    expect(find.text('Neues Spiel'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('chess: select a pawn and move it', (tester) async {
    await tester.pumpWidget(app(const ChessScreen(setup: PlaySetup.local())));
    expect(find.text('Weiß ist am Zug'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sqe2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sqe4')));
    await tester.pump();
    expect(find.text('Schwarz ist am Zug'), findsOneWidget);
  });

  testWidgets('dame: move a stone', (tester) async {
    await tester.pumpWidget(
      app(const CheckersScreen(setup: PlaySetup.local())),
    );
    expect(find.textContaining('Weiß ist am Zug'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ck5-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ck4-1')));
    await tester.pump();
    expect(find.textContaining('Schwarz ist am Zug'), findsOneWidget);
  });

  testWidgets('mühle: place stones', (tester) async {
    await tester.pumpWidget(app(const MillScreen(setup: PlaySetup.local())));
    expect(find.text('Weiß setzt (noch 9)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mill0')));
    await tester.pump();
    expect(find.text('Schwarz setzt (noch 9)'), findsOneWidget);
  });

  testWidgets('darts solo: choose mode and throw three darts', (tester) async {
    await tester.pumpWidget(
      app(const DartsScreen(setup: PlaySetup.local(players: 1))),
    );
    await tester.tap(find.byKey(const ValueKey('dartsStart')));
    await tester.pump();
    expect(find.textContaining('Du wirfst (Dart 1/3)'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('dartBoard')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Du wirfst (Dart 1/3)'), findsOneWidget);
    expect(find.textContaining('Darts: 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kniffel solo: roll and score', (tester) async {
    await tester.pumpWidget(
      app(const YahtzeeScreen(setup: PlaySetup.local(players: 1))),
    );
    await tester.tap(find.byKey(const ValueKey('rollButton')));
    await tester.pump();
    expect(find.textContaining('noch 2 Würfe'), findsOneWidget);
    final cell = find.byKey(const ValueKey('score-0-chance'));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pump();
    expect(find.textContaining('noch 3 Würfe'), findsOneWidget);
  });

  testWidgets('battleship vs computer: place fleet and fire', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const BattleshipScreen(setup: PlaySetup.ai())));
    expect(find.text('Stelle deine Flotte auf'), findsOneWidget);
    await tester.tap(find.text('Bereit'));
    await tester.pump();
    expect(find.text('Dein Schuss!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bs4-4')));
    await tester.pump();
    expect(find.textContaining('Du:'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('battleship: place the fleet by hand', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const BattleshipScreen(setup: PlaySetup.ai())));
    await tester.tap(find.text('Leeren'));
    await tester.pump();
    bool readyEnabled() =>
        tester
            .widget<ButtonStyleButton>(find.byKey(const ValueKey('fleetReady')))
            .onPressed !=
        null;
    expect(readyEnabled(), isFalse);
    // Rows 0, 2, 4, 6, 8: 5, 4, 3, 3, 2 horizontally from x = 0.
    for (final y in [0, 2, 4, 6, 8]) {
      await tester.tap(find.byKey(ValueKey('place0-$y')));
      await tester.pump();
    }
    expect(find.text('Flotte vollständig'), findsOneWidget);
    expect(readyEnabled(), isTrue);
    // Picking a ship up again makes the fleet incomplete.
    await tester.tap(find.byKey(const ValueKey('place0-8')));
    await tester.pump();
    expect(readyEnabled(), isFalse);
    // Place it vertically instead.
    await tester.tap(find.byKey(const ValueKey('rotateShip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('place9-0')));
    await tester.pump();
    expect(readyEnabled(), isTrue);
    await tester.tap(find.byKey(const ValueKey('fleetReady')));
    await tester.pump();
    expect(find.text('Dein Schuss!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('battleship pass and play hides boards between turns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const BattleshipLocalScreen()));
    expect(find.text('Gerät an Spieler 1 übergeben'), findsOneWidget);
    await tester.tap(find.text('Ich bin bereit'));
    await tester.pump();
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    expect(find.text('Gerät an Spieler 2 übergeben'), findsOneWidget);
    await tester.tap(find.text('Ich bin bereit'));
    await tester.pump();
    await tester.tap(find.text('Fertig'));
    await tester.pump();
    await tester.tap(find.text('Ich bin bereit'));
    await tester.pump();
    expect(find.text('Spieler 1 schießt'), findsOneWidget);
  });

  testWidgets('snake starts and runs', (tester) async {
    await tester.pumpWidget(app(const SnakeScreen()));
    await tester.tap(find.byKey(const ValueKey('snakeStart')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Punkte:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('single player screens build', (tester) async {
    await tester.pumpWidget(app(const MahjongScreen()));
    await tester.pump();
    expect(find.textContaining('Steine:'), findsOneWidget);

    await tester.pumpWidget(app(const LabyrinthLevelsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Aufwärmen'), findsOneWidget);

    await tester.pumpWidget(app(const BilliardScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Stöße'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('online connect four between two players over the relays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final rooms = (await tester.runAsync(
      () => buildRoom(
        FakeRelayBus(),
        1,
        gameId: 'connect_four',
        names: ['Anna', 'Ben'],
      ),
    ))!;
    final sa = rooms[0], sb = rooms[1];
    await tester.pumpWidget(
      app(
        Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('A'),
                child: ConnectFourScreen(setup: PlaySetup.online(sa)),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('B'),
                child: ConnectFourScreen(setup: PlaySetup.online(sb)),
              ),
            ),
          ],
        ),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }

    await settle();
    final a = find.byKey(const ValueKey('A')),
        b = find.byKey(const ValueKey('B'));
    expect(
      find.descendant(of: a, matching: find.textContaining('Du bist am Zug')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: b,
        matching: find.textContaining('Anna (Rot) ist am Zug'),
      ),
      findsOneWidget,
    );

    // B may not move out of turn.
    await tester.tap(
      find.descendant(of: b, matching: find.byKey(const ValueKey('c4col3'))),
    );
    await settle();
    expect(
      find.descendant(
        of: b,
        matching: find.textContaining('Anna (Rot) ist am Zug'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: a, matching: find.byKey(const ValueKey('c4col3'))),
    );
    await settle();
    expect(
      find.descendant(of: b, matching: find.textContaining('Du bist am Zug')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: a,
        matching: find.textContaining('Ben (Gelb) ist am Zug'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });

  testWidgets('online 8-ball: shot is mirrored and the turn passes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = (await tester.runAsync(
      () => buildRoom(
        FakeRelayBus(),
        1,
        gameId: 'billiard',
        names: ['Anna', 'Ben'],
      ),
    ))!;
    await tester.pumpWidget(
      app(
        Column(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('A'),
                child: EightBallScreen(setup: PlaySetup.online(rooms[0])),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('B'),
                child: EightBallScreen(setup: PlaySetup.online(rooms[1])),
              ),
            ),
          ],
        ),
      ),
    );
    final a = find.byKey(const ValueKey('A')),
        b = find.byKey(const ValueKey('B'));
    expect(
      find.descendant(of: a, matching: find.text('Du bist am Stoß')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('Anna ist am Stoß')),
      findsOneWidget,
    );
    // Anna drags away from the cue ball (left of it) and releases: break shot.
    final table = find.descendant(
      of: a,
      matching: find.byKey(const ValueKey('poolTable')),
    );
    final rect = tester.getRect(table);
    final cue = Offset(
      rect.left + rect.width * (0.06 + 0.5) / 2.12,
      rect.center.dy,
    );
    await tester.dragFrom(cue - const Offset(60, 0), const Offset(-120, 0));
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Both devices agree on whose turn it is after the shot.
    final aTurn = find
        .descendant(of: a, matching: find.text('Du bist am Stoß'))
        .evaluate()
        .isNotEmpty;
    final bTurn = find
        .descendant(of: b, matching: find.text('Du bist am Stoß'))
        .evaluate()
        .isNotEmpty;
    expect(aTurn != bTurn, isTrue, reason: 'exactly one player is to shoot');
    final event = find.textContaining(RegExp('versenkt|Foul|Nichts'));
    expect(find.descendant(of: a, matching: event), findsOneWidget);
    expect(find.descendant(of: b, matching: event), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });
}
