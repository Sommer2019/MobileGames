import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/leaderboard.dart';
import 'package:mobile_games/ui/leaderboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Leaderboard.instance = null;
  });

  test(
    'personal list keeps the best 10, record detection per direction',
    () async {
      expect(await Leaderboard.submit('snake', 5), isTrue);
      expect(await Leaderboard.submit('snake', 3), isFalse);
      expect(await Leaderboard.submit('snake', 9), isTrue);
      for (var i = 0; i < 12; i++) {
        await Leaderboard.submit('snake', 1);
      }
      final h = await Leaderboard.history('snake');
      expect(h.length, Leaderboard.keep);
      expect(h.take(3).map((e) => e.value), [9, 5, 3]);

      // Fewer darts are better.
      expect(await Leaderboard.submit('darts.x501', 30), isTrue);
      expect(await Leaderboard.submit('darts.x501', 40), isFalse);
      expect(await Leaderboard.submit('darts.x501', 20), isTrue);
      expect(await Leaderboard.best('darts.x501'), 20);
      // Impossible values are ignored.
      expect(await Leaderboard.submit('darts.x501', 3), isFalse);
      expect(await Leaderboard.best('darts.x501'), 20);
    },
  );

  test('old best values are taken over', () async {
    SharedPreferences.setMockInitialValues({'snake.best': 42});
    expect(await Leaderboard.best('snake'), 42);
    expect(await Leaderboard.submit('snake', 40), isFalse);
    expect((await Leaderboard.bests())['snake'], 42);
  });

  test('scores are shared over the relays and ranked', () async {
    final bus = FakeRelayBus();
    final a = await Account.load(prefix: 'a');
    final b = await Account.load(prefix: 'b');
    await a.setName('Anna');
    await b.setName('Ben');
    final la = Leaderboard(bus.client(), a);
    final lb = Leaderboard(bus.client(), b);

    await Leaderboard.submit('mahjong.tower', 300);
    await la.publish();
    SharedPreferences.setMockInitialValues({});
    await Leaderboard.submit('mahjong.tower', 200);
    await Leaderboard.submit('snake', 7);
    await lb.publish();

    final all = await la.fetch(timeout: const Duration(milliseconds: 50));
    expect(all.length, 2);
    final ranked = Leaderboard.rank(boardById('mahjong.tower'), all);
    expect(ranked.map((r) => r.$1.name), ['Ben', 'Anna']);
    expect(Leaderboard.rank(boardById('snake'), all).single.$2, 7);

    final onlyA = await lb.fetch(
      authors: [a.keys.publicKey],
      timeout: const Duration(milliseconds: 50),
    );
    expect(onlyA.single.name, 'Anna');
    expect(boardById('mahjong.tower').format(125), '2:05');
  });

  testWidgets('leaderboard screen shows own results offline', (tester) async {
    await Leaderboard.submit('klondike', 1234);
    await tester.pumpWidget(
      const MaterialApp(home: LeaderboardScreen(game: 'klondike')),
    );
    await tester.pumpAndSettle();
    expect(find.text('1234 Punkte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-snake')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch kein Ergebnis'), findsOneWidget);
  });
}
