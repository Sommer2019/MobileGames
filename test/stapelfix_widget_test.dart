import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/stapelfix/stapelfix_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('discarding ends the turn, the computer plays', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: StapelfixScreen(setup: PlaySetup.local(players: 2, bots: {1})),
      ),
    );
    var turns = 0;
    for (var i = 0; i < 300 && turns < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.textContaining('Du bist dran').evaluate().isEmpty) continue;
      turns++;
      final hand = find.byWidgetPredicate(
        (w) => w is GestureDetector && '${w.key}'.contains('sfHand'),
      );
      await tester.tap(hand.first);
      await tester.pump();
      expect(find.textContaining('ablegen'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sfDiscard0')));
      await tester.pump();
      expect(find.textContaining('Du bist dran'), findsNothing);
    }
    expect(turns, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
