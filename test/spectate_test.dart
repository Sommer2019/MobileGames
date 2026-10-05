import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/net/game_session.dart';
import 'package:mobile_games/games/chess/chess_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:mobile_games/core/net/matchmaker.dart';
import 'package:mobile_games/core/net/messenger.dart';
import 'package:mobile_games/core/net/room.dart';
import 'package:mobile_games/core/net/spectate.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

/// Host and one guest in a chess room; the guest's device can be watched.
Future<(GameRoom, GameRoom)> chessRoom(
  FakeRelayBus bus,
  Messenger hostMsg,
  Messenger guestMsg,
) async {
  final host = RoomHost(
    gameId: 'chess',
    maxPlayers: 2,
    myName: 'Hanna',
    sessionFactory: factoryFor(hostMsg),
  );
  host.addGuest(
    MatchInfo(
      matchId: 'm',
      gameId: 'chess',
      opponent: guestMsg.me,
      opponentName: 'Gerd',
      isHost: true,
    ),
  );
  final guest = RoomGuest(
    MatchInfo(
      matchId: 'm',
      gameId: 'chess',
      opponent: hostMsg.me,
      opponentName: 'Hanna',
      isHost: false,
    ),
    factoryFor(guestMsg),
  );
  for (var i = 0; i < 50 && host.connected.isEmpty; i++) {
    await pump();
  }
  final hostRoom = host.start();
  return (hostRoom, await guest.room);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a friend watches: earlier moves, live moves and cheers', () async {
    final bus = FakeRelayBus();
    final gerd = await Account.load(prefix: 'g', recover: () async => null);
    final wanda = await Account.load(prefix: 'w', recover: () async => null);
    await gerd.addFriend(wanda.keys.publicKey, name: 'Wanda');
    final hostMsg = newMessenger(bus);
    final gerdMsg = Messenger(bus.client(), gerd.keys)..start();
    final wandaMsg = Messenger(bus.client(), wanda.keys)..start();
    final (hostRoom, gerdRoom) = await chessRoom(bus, hostMsg, gerdMsg);

    final hub = SpectatorHub(gerdMsg, gerd, factoryFor(gerdMsg));
    hub.attach(gerdRoom);
    expect(hub.playing.value, 'chess');

    hostRoom.send({'t': 'move', 'from': 'e2', 'to': 'e4'});
    await pump(100);
    gerdRoom.send({'t': 'move', 'from': 'e7', 'to': 'e5'});
    await pump(100);

    final watched = await watchFriend(
      messenger: wandaMsg,
      sessionFactory: factoryFor(wandaMsg),
      friend: Friend(gerd.keys.publicKey, 'Gerd'),
      timeout: const Duration(seconds: 5),
    );
    expect(watched.spectator, isTrue);
    expect(watched.gameId, 'chess');
    expect(watched.mySeat, 1, reason: 'seen from Gerd’s side');
    expect(watched.names, ['Hanna', 'Gerd']);
    expect(hub.watchers.value, 1);

    final seen = <RoomMessage>[];
    watched.messages.listen(seen.add);
    await pump();
    expect([for (final m in seen) m.data['to']], ['e4', 'e5']);
    expect([for (final m in seen) m.seat], [0, 1]);

    // Live: the host's next move arrives through Gerd.
    hostRoom.send({'t': 'move', 'from': 'g1', 'to': 'f3'});
    for (var i = 0; i < 40 && seen.length < 3; i++) {
      await pump();
    }
    expect(seen.last.data['to'], 'f3');

    // Spectators can't play.
    watched.send({'t': 'move', 'from': 'a7', 'to': 'a6'});
    await pump(100);
    expect(gerdRoom.log.length, 3);

    // A cheer reaches both players.
    final hostCheers = <Reaction>[];
    hostRoom.reactions.listen(hostCheers.add);
    final gerdCheers = <Reaction>[];
    gerdRoom.reactions.listen(gerdCheers.add);
    watched.react('Wanda', '🎉');
    for (var i = 0; i < 40 && hostCheers.isEmpty; i++) {
      await pump();
    }
    expect(gerdCheers.single.emoji, '🎉');
    expect(hostCheers.single.name, 'Wanda');
    // Only known emojis.
    watched.react('Wanda', '💩');
    await pump(100);
    expect(gerdCheers, hasLength(1));

    hub.detach(gerdRoom);
    expect(hub.playing.value, isNull);
    await watched.close();
    await hostRoom.close();
    await gerdRoom.close();
  });

  test('strangers and games without a running room are refused', () async {
    final bus = FakeRelayBus();
    final gerd = await Account.load(prefix: 'g', recover: () async => null);
    final stranger = await Account.load(prefix: 's', recover: () async => null);
    final gerdMsg = Messenger(bus.client(), gerd.keys)..start();
    final strangerMsg = Messenger(bus.client(), stranger.keys)..start();
    final hub = SpectatorHub(gerdMsg, gerd, factoryFor(gerdMsg));
    final (_, gerdRoom) = await chessRoom(bus, newMessenger(bus), gerdMsg);
    hub.attach(gerdRoom);

    await expectLater(
      watchFriend(
        messenger: strangerMsg,
        sessionFactory: factoryFor(strangerMsg),
        friend: Friend(gerd.keys.publicKey, 'Gerd'),
        timeout: const Duration(seconds: 3),
      ),
      throwsA(isA<WatchRefused>()),
    );
    expect(hub.watchers.value, 0);
    await hub.dispose();
  });

  testWidgets('the spectator board follows both players and cannot move', (
    tester,
  ) async {
    final bus = FakeRelayBus();
    final link = GameSession(
      MatchInfo(
        matchId: 'w',
        gameId: 'watch',
        opponent: KeyPair.generate().publicKey,
        opponentName: 'Gerd',
        isHost: false,
      ),
      newMessenger(bus),
    );
    final room = GameRoom.watching(
      gameId: 'chess',
      seat: 1,
      names: ['Hanna', 'Gerd'],
      link: link,
      log: [
        {
          's': 0,
          'd': {'t': 'move', 'from': 'e2', 'to': 'e4'},
        },
        {
          's': 1,
          'd': {'t': 'move', 'from': 'e7', 'to': 'e5'},
        },
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: ChessScreen(setup: PlaySetup.online(room))),
    );
    await tester.pump();
    expect(find.text('👁 Du schaust Gerd zu'), findsOneWidget);
    // Both moves were applied: white to move again.
    expect(find.textContaining('Hanna ist am Zug'), findsOneWidget);
    // A cheer button is there; the board ignores taps.
    expect(find.byKey(const ValueKey('react🎉')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('react🎉')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('🎉'), findsWidgets);
    await tester.pump(const Duration(seconds: 8));
  });
}
