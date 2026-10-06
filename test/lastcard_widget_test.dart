import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/lastcard/lastcard_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('playing against three computers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: LastCardScreen(
          setup: PlaySetup.local(players: 4, bots: {1, 2, 3}),
        ),
      ),
    );
    var myTurns = 0;
    for (var i = 0; i < 400 && myTurns < 15; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      if (find.textContaining('Du bist dran').evaluate().isEmpty) continue;
      if (find.textContaining('gewinnt').evaluate().isNotEmpty) break;
      myTurns++;
      final call = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Letzte Karte!'),
          matching: find.byType(FilledButton),
        ),
      );
      if (call.onPressed != null) {
        call.onPressed!();
        await tester.pump();
      }
      final keep = find.byKey(const ValueKey('lcKeep'));
      // Try the hand cards from the left; a wild opens the colour choice.
      final cards = find.byWidgetPredicate(
        (w) =>
            w is GestureDetector &&
            '${w.key}'.contains("'lc") &&
            !'${w.key}'.contains('lcPile'),
      );
      var played = false;
      for (final e in cards.evaluate().toList()) {
        await tester.tap(find.byKey(e.widget.key!), warnIfMissed: false);
        await tester.pump();
        if (find.text('Welche Farbe?').evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const ValueKey('lcColor0')));
          await tester.pumpAndSettle();
        }
        if (find.textContaining('Du bist dran').evaluate().isEmpty) {
          played = true;
          break;
        }
      }
      if (!played) {
        if (keep.evaluate().isNotEmpty) {
          await tester.tap(keep);
        } else {
          await tester.tap(find.byKey(const ValueKey('lcPile')));
        }
        await tester.pump();
      }
    }
    expect(myTurns, greaterThan(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
