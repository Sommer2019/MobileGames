import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/arrows/arrows_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hints lead through level 1 to level 2', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ArrowsScreen(startLevel: 1)),
    );
    expect(find.text('Level 1'), findsOneWidget);
    // The hint colours a free arrow amber; tap where it is by asking the
    // board for each cell is fiddly, so tap all cells until done.
    final board = tester.getRect(find.byKey(const ValueKey('arrowsBoard')));
    for (var round = 0; round < 60; round++) {
      if (find.text('Nächstes Level').evaluate().isNotEmpty) break;
      await tester.tap(find.byKey(const ValueKey('arrowsHint')));
      await tester.pump();
      final state = tester.state(find.byType(ArrowsScreen)) as dynamic;
      final hint = state.hintCell as Offset?;
      if (hint == null) break;
      await tester.tapAt(board.topLeft + hint);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Nächstes Level'), findsOneWidget);
    await tester.tap(find.text('Nächstes Level'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Level 2'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('arrows.level'), 2);
  });
}
