import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/bingo/bingo_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('balls are drawn until a computer calls bingo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: BingoScreen(setup: PlaySetup.local(players: 4, bots: {1, 2, 3})),
      ),
    );
    expect(find.text('BINGO!'), findsOneWidget);
    // Nobody marks the own card here, so a computer calls bingo.
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.textContaining('hat Bingo').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('hat Bingo'), findsOneWidget);
    expect(find.byKey(const ValueKey('bingoCall')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
