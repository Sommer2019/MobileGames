import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/lastcard/lastcard_screen.dart';
import 'package:mobile_games/games/stapelfix/stapelfix_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> twoScreens(
    WidgetTester tester,
    String gameId,
    Widget Function(PlaySetup) build,
  ) async {
    tester.view.physicalSize = const Size(2200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = (await tester.runAsync(
      () => buildRoom(
        FakeRelayBus(),
        1,
        gameId: gameId,
        names: ['Anna', 'Ben'],
        bots: 1,
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('A'),
                child: build(PlaySetup.online(rooms[0])),
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('B'),
                child: build(PlaySetup.online(rooms[1])),
              ),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }
  }

  testWidgets('Letzte Karte: the guest gets the host deal', (tester) async {
    await twoScreens(tester, 'lastcard', (s) => LastCardScreen(setup: s));
    int? top(String side) => tester
        .widgetList<LcCardView>(
          find.descendant(
            of: find.byKey(ValueKey(side)),
            matching: find.byType(LcCardView),
          ),
        )
        .firstWhere((w) => w.width == 96)
        .card;
    expect(top('A'), isNotNull);
    expect(top('B'), top('A'));
    final guestHand = find.descendant(
      of: find.byKey(const ValueKey('B')),
      matching: find.byWidgetPredicate((w) => w is LcCardView && w.width == 52),
    );
    expect(guestHand, findsNWidgets(7));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Stapelfix: both see the same stock cards', (tester) async {
    await twoScreens(tester, 'stapelfix', (s) => StapelfixScreen(setup: s));
    List<int?> stocks(String side) => [
      for (final w in tester.widgetList<SfCardView>(
        find.descendant(
          of: find.byKey(ValueKey(side)),
          matching: find.byType(SfCardView),
        ),
      ))
        if (w.width == 76 || w.width == 32) w.card,
    ];
    // Host: own stock + guest and computer; guest: the same three cards.
    expect(stocks('A').toSet(), stocks('B').toSet());
    expect(stocks('A').length, 3);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
