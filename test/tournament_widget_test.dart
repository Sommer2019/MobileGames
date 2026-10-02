import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/tournament/tournament_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

void main() {
  testWidgets('two friends play a connect four tournament', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = (await tester.runAsync(
      () => buildRoom(
        FakeRelayBus(),
        1,
        gameId: tournamentId,
        names: ['Anna', 'Ben'],
        options: {
          'games': ['connect_four'],
          'rounds': 2,
        },
      ),
    ))!;
    Widget side(String key, int i) => Expanded(
      child: KeyedSubtree(
        key: ValueKey(key),
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: tournamentRouteSettings(),
            builder: (_) => TournamentScreen(setup: PlaySetup.online(rooms[i])),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Row(children: [side('A', 0), side('B', 1)])),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    final a = find.byKey(const ValueKey('A'));
    final b = find.byKey(const ValueKey('B'));
    expect(
      find.descendant(of: a, matching: find.textContaining('Partie 1 von 2')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: a, matching: find.byKey(const ValueKey('tourNext'))),
    );
    await settle();
    // Both are in the game now; Anna (red) wins with four in column 0.
    for (final (who, col) in [
      (a, 0),
      (b, 1),
      (a, 0),
      (b, 1),
      (a, 0),
      (b, 1),
      (a, 0),
    ]) {
      await tester.tap(
        find.descendant(of: who, matching: find.byKey(ValueKey('c4col$col'))),
      );
      await settle();
    }
    expect(
      find.descendant(of: a, matching: find.text('Du hast gewonnen! 🎉')),
      findsOneWidget,
    );
    for (final who in [a, b]) {
      await tester.tap(
        find.descendant(
          of: who,
          matching: find.byKey(const ValueKey('toTournament')),
        ),
      );
      await settle();
    }
    // Standings: Anna 3 points, next match is game 2.
    expect(find.descendant(of: a, matching: find.text('3 P')), findsOneWidget);
    expect(find.descendant(of: b, matching: find.text('3 P')), findsOneWidget);
    expect(
      find.descendant(of: b, matching: find.textContaining('Partie 2 von 2')),
      findsOneWidget,
    );

    // Match 2: the starting player rotates, so Ben begins and wins.
    await tester.tap(
      find.descendant(of: a, matching: find.byKey(const ValueKey('tourNext'))),
    );
    await settle();
    for (final (who, col) in [
      (b, 0),
      (a, 1),
      (b, 0),
      (a, 1),
      (b, 0),
      (a, 1),
      (b, 0),
    ]) {
      await tester.tap(
        find.descendant(of: who, matching: find.byKey(ValueKey('c4col$col'))),
      );
      await settle();
    }
    for (final who in [a, b]) {
      await tester.tap(
        find.descendant(
          of: who,
          matching: find.byKey(const ValueKey('toTournament')),
        ),
      );
      await settle();
    }
    for (final who in [a, b]) {
      expect(
        find.descendant(of: who, matching: find.textContaining('Gleichstand')),
        findsOneWidget,
      );
    }

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  });
}
