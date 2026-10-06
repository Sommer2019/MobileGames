import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/boxes/boxes_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('drawing a line, then the computer answers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BoxesScreen(setup: PlaySetup.local(players: 2, bots: {1})),
      ),
    );
    expect(find.text('Du bist dran'), findsOneWidget);
    // Tap near the top edge of the board: a horizontal line.
    final board = tester.getRect(find.byKey(const ValueKey('boxesBoard')));
    await tester.tapAt(Offset(board.left + board.width / 10, board.top + 2));
    await tester.pump();
    expect(find.text('Computer überlegt …'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Du bist dran'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
