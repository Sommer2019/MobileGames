import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/halma/halma_logic.dart';
import 'package:mobile_games/games/halma/halma_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('selecting a piece, moving, computer answers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: HalmaScreen(setup: PlaySetup.local(players: 2, bots: {1})),
      ),
    );
    expect(find.textContaining('Figur wählen'), findsOneWidget);
    final board = tester.getRect(find.byKey(const ValueKey('halmaBoard')));
    // Bottom arm: the front row is the 4th row from the bottom tip.
    final unit = board.width / (2 * 12.9);
    final centre = board.center;
    final front = centre + Offset(-unit * 3 * 0.866 * 2 / 2, 1.5 * 5 * unit);
    await tester.tapAt(front);
    await tester.pump();
    expect(find.textContaining('Ziel wählen'), findsOneWidget);
    await tester.tapAt(front - Offset(0, 1.5 * unit) + Offset(0.866 * unit, 0));
    await tester.pump();
    expect(find.textContaining('überlegt'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Figur wählen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(HalmaBoard.cells.length, 121);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
