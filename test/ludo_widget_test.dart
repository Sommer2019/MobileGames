import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/ludo/ludo_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rolling, then the computers take their turns', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LudoScreen(setup: PlaySetup.local(players: 4, bots: {1, 2, 3})),
      ),
    );
    expect(find.textContaining('Du bist dran'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ludoDie')));
    // Let the die tumble and all bots play for a while.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('ludoBoard')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
