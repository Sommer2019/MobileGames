import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/saved_games.dart';
import 'package:mobile_games/games/prophet/prophet_logic.dart';
import 'package:mobile_games/games/prophet/prophet_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('predicting and playing against three computers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProphetScreen(
          setup: PlaySetup.local(players: 4, bots: {1, 2, 3}),
        ),
      ),
    );
    var bids = 0, plays = 0;
    for (var i = 0; i < 600 && bids < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byKey(const ValueKey('trump0')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('trump0')));
        continue;
      }
      if (find.byKey(const ValueKey('bid1')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('bid1')));
        bids++;
        continue;
      }
      final next = find.byKey(const ValueKey('prophetNext'));
      if (next.evaluate().isNotEmpty) {
        await tester.tap(next);
        continue;
      }
      if (find.text('Du bist dran').evaluate().isEmpty) continue;
      // Play the first card that may be played.
      final cards = find.byWidgetPredicate(
        (w) =>
            w is GestureDetector &&
            '${w.key}'.contains("'pc") &&
            w.onTap != null,
      );
      if (cards.evaluate().isEmpty) continue;
      await tester.tap(cards.first);
      plays++;
    }
    expect(bids, 4, reason: 'reached round 4');
    expect(plays, greaterThanOrEqualTo(6), reason: '1 + 2 + 3 cards');
    expect(find.textContaining('Runde 4/15'), findsOneWidget);

    // The score table lists the finished rounds.
    await tester.tap(find.byKey(const ValueKey('prophetScores')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prophetScoreTable')), findsOneWidget);
    expect(find.text('Gesamt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('a wizard turns up: the dealer picks trump (small screen)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // A deal where a wizard shows trump; seat 0 (me) deals round 1.
    var seed = 0;
    while (true) {
      final g = ProphetGame(players: 4)..apply(['deal', seed]);
      if (g.phase == ProphetPhase.trumpChoice) break;
      seed++;
    }
    SharedPreferences.setMockInitialValues({
      'save.prophet.local4b123': jsonEncode({
        'round': 0,
        'events': [
          ['deal', seed],
        ],
      }),
    });
    await SavedGames.load();
    addTearDown(SavedGames.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProphetScreen(
          setup: PlaySetup.local(players: 4, bots: {1, 2, 3}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Trumpf wird gewählt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('trump2')));
    await tester.pump();
    expect(find.text('Trumpf: Grün'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });
}
