import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/saved_games.dart';
import 'package:mobile_games/games/mahjong/mahjong_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedGames.reset();
  });

  testWidgets('the shape can be chosen and is remembered', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: MahjongScreen()));
    await tester.pump();
    // Portrait starts with the pyramid.
    expect(find.textContaining('Pyramide'), findsOneWidget);
    expect(find.textContaining('Steine: 108'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mahjongShape')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shape-tower')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Turm'), findsOneWidget);
    expect(find.textContaining('Steine: 104'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mahjong.shape'), 'tower');
    await tester.pumpWidget(const SizedBox());
  });
}
