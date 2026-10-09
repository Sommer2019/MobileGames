import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/net/game_session.dart';
import 'package:mobile_games/core/net/matchmaker.dart';
import 'package:mobile_games/core/net/room.dart';
import 'package:mobile_games/core/net/spectate.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:mobile_games/games/registry.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every online game can be watched', () {
    for (final g in games) {
      if (g.multiplayerBuilder == null) continue;
      expect(SpectatorHub.watchable, contains(g.id), reason: g.title);
    }
  });

  for (final game in games.where((g) => g.multiplayerBuilder != null)) {
    testWidgets('${game.title}: a spectator joins a running game', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final bus = FakeRelayBus();
      final rooms = (await tester.runAsync(
        () => buildRoom(bus, 1, gameId: game.id, names: ['Anna', 'Ben']),
      ))!;
      final host = rooms[0];
      // The host's screen deals, rolls or simply starts.
      await tester.pumpWidget(
        MaterialApp(home: game.multiplayerBuilder!(PlaySetup.online(host))),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final logged = host.log.length;
      // A friend of Ben's joins with what happened so far.
      final link = GameSession(
        MatchInfo(
          matchId: 'w',
          gameId: 'watch',
          opponent: KeyPair.generate().publicKey,
          opponentName: 'Ben',
          isHost: false,
        ),
        newMessenger(bus),
      );
      final watching = GameRoom.watching(
        gameId: game.id,
        seat: 1,
        names: host.names,
        options: host.options,
        link: link,
        log: [for (final e in host.log) Map<String, dynamic>.from(e)],
      );
      await tester.pumpWidget(
        MaterialApp(home: game.multiplayerBuilder!(PlaySetup.online(watching))),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('👁 Du schaust Ben zu'), findsOneWidget);
      // Watching changes nothing in the game.
      expect(host.log.length, logged);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
      await tester.runAsync(() async {
        await watching.close();
        for (final r in rooms) {
          await r.close();
        }
      });
    });
  }
}
