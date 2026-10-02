import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/billiard/billiard_screen.dart';
import 'package:mobile_games/games/chess/chess_screen.dart';
import 'package:mobile_games/games/connect_four/connect_four_screen.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_screen.dart';
import 'package:mobile_games/games/mahjong/mahjong_screen.dart';
import 'package:mobile_games/games/battleship/battleship_screen.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_screen.dart';
import 'package:mobile_games/ui/home_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

Widget app(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home lists all seven games', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    for (final title in [
      'Schach',
      'Schiffe versenken',
      '4 gewinnt',
      'Kniffel',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Billard'), 200);
    for (final title in ['Kugellabyrinth', 'Mahjong', 'Billard']) {
      expect(find.text(title), findsOneWidget);
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
      find.descendant(of: b, matching: find.textContaining('Anna (Rot) ist am Zug')),
      findsOneWidget,
    );

    // B may not move out of turn.
    await tester.tap(
      find.descendant(of: b, matching: find.byKey(const ValueKey('c4col3'))),
    );
    await settle();
    expect(
      find.descendant(of: b, matching: find.textContaining('Anna (Rot) ist am Zug')),
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
      find.descendant(of: a, matching: find.textContaining('Ben (Gelb) ist am Zug')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });
}
