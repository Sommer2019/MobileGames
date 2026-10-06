import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/domino/domino_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('playing a round against the computer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: DominoScreen(setup: PlaySetup.local(players: 2, bots: {1})),
      ),
    );
    // Seat 0 starts the first round: play any tile.
    for (var i = 0; i < 40; i++) {
      final draw = find.byKey(const ValueKey('dominoDraw'));
      final pass = find.byKey(const ValueKey('dominoPass'));
      final next = find.byKey(const ValueKey('dominoNext'));
      if (next.evaluate().isNotEmpty) break;
      if (draw.evaluate().isNotEmpty) {
        await tester.tap(draw);
      } else if (pass.evaluate().isNotEmpty) {
        await tester.tap(pass);
      } else {
        final end = find.byKey(const ValueKey('dominoEnd1'));
        if (end.evaluate().isNotEmpty) {
          await tester.tap(end);
        } else {
          final tiles = find.byWidgetPredicate(
            (w) =>
                w is DominoTile &&
                w.highlight != null &&
                w.vertical &&
                w.size == 26,
          );
          if (tiles.evaluate().isNotEmpty) await tester.tap(tiles.first);
        }
      }
      await tester.pump(const Duration(seconds: 1));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
