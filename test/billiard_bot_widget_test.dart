import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/billiard/eight_ball_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the computer breaks and the turn moves on', (tester) async {
    tester.view.physicalSize = const Size(2200, 1080);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // The computer sits on seat 0, so it has the break.
    await tester.pumpWidget(
      const MaterialApp(
        home: EightBallScreen(setup: PlaySetup.local(players: 2, bots: {0})),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('zielt'), findsOneWidget);
    var humanTurn = false;
    for (var i = 0; i < 400 && !humanTurn; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      humanTurn = find.text('Du bist am Stoß').evaluate().isNotEmpty;
    }
    expect(tester.takeException(), isNull);
    // Either the computer potted and goes on, or it is our turn now.
    expect(
      humanTurn || find.textContaining('zielt').evaluate().isNotEmpty,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
