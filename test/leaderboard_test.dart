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

  test('a new phone takes over the published bests', () async {
    final bus = FakeRelayBus();
    final a = await Account.load(prefix: 'a');
    await a.setName('Anna');
    // Old phone.
    await Leaderboard.submit('snake', 41);
    await Leaderboard.submit('mahjong.tower', 300);
    for (var i = 0; i < 3; i++) {
      await Leaderboard.recordWin('chess.grandmaster');
    }
    await Leaderboard(bus.client(), a).publish();

    // New phone, same account: nothing on the device yet.
    SharedPreferences.setMockInitialValues({});
    final moved = Leaderboard(bus.client(), a);
    Leaderboard.instance = moved;
    expect(await Leaderboard.submit('snake', 6), isTrue);
    await moved.publish();

    expect(await Leaderboard.best('snake'), 41, reason: 'shown under "Ich"');
    expect(await Leaderboard.best('mahjong.tower'), 300);
    final h = await Leaderboard.history('snake');
    expect(h.map((e) => e.value), [41, 6]);
    // Wins go on counting from 3.
    await Leaderboard.recordWin('chess.grandmaster');
    expect(await Leaderboard.best('chess.grandmaster'), 4);

    // The published values were not replaced with lower ones.
    final remote = await moved.fetch(
      authors: [a.keys.publicKey],
      timeout: const Duration(milliseconds: 50),
    );
    expect(remote.single.scores['snake'], 41);
    expect(remote.single.scores['mahjong.tower'], 300);
  });

  testWidgets('leaderboard screen shows own results offline', (tester) async {
    await Leaderboard.submit('klondike', 1234);
    await tester.pumpWidget(
      const MaterialApp(home: LeaderboardScreen(game: 'klondike')),
    );
    await tester.pumpAndSettle();
    expect(find.text('1234 Punkte'), findsOneWidget);
    Future<void> pick(String game) async {
      await tester.tap(find.byKey(const ValueKey('lbGamePicker')));
      await tester.pumpAndSettle();
      final tile = find.byKey(ValueKey('lbGame-$game'));
      await tester.scrollUntilVisible(
        tile,
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    await pick('snake');
    expect(find.textContaining('Noch kein Ergebnis'), findsOneWidget);
    // Games with several boards show their modes in a second row.
    expect(find.byKey(const ValueKey('board-darts.x301')), findsNothing);
    await pick('darts');

    await tester.pumpAndSettle();
    expect(find.text('301'), findsOneWidget);
    expect(find.text('Rund um die Uhr'), findsOneWidget);
  });

  test('variant names drop the game name', () {
    expect(variantLabel(boardById('arrows.hard')), 'Schwer');
    expect(variantLabel(boardById('labyrinth')), 'Normal');
    expect(variantLabel(boardById('labyrinth.rubber')), 'Gummiball 🎮');
    expect(variantLabel(boardById('kniffel')), 'Allein');
  });
}
