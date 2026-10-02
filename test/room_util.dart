import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/net/game_session.dart';
import 'package:mobile_games/core/net/matchmaker.dart';
import 'package:mobile_games/core/net/messenger.dart';
import 'package:mobile_games/core/net/room.dart';
import 'package:mobile_games/core/nostr/keys.dart';

import 'fake_nostr.dart';

Future<void> pump([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Messenger newMessenger(FakeRelayBus bus) =>
    Messenger(bus.client(), KeyPair.generate())..start();

SessionFactory factoryFor(Messenger m) =>
    (match) =>
        GameSession(match, m, helloInterval: const Duration(milliseconds: 30));

/// Builds a started room with a host and [guests] guests.
Future<List<GameRoom>> buildRoom(
  FakeRelayBus bus,
  int guests, {
  String gameId = 'g',
  List<String>? names,
  Map<String, dynamic> options = const {'mode': 'x'},
}) async {
  final hostMsg = newMessenger(bus);
  final host = RoomHost(
    gameId: gameId,
    maxPlayers: guests + 1,
    myName: names?[0] ?? 'Host',
    sessionFactory: factoryFor(hostMsg),
  );
  final guestRooms = <Future<GameRoom>>[];
  for (var i = 0; i < guests; i++) {
    final gm = newMessenger(bus);
    final id = 'm$i';
    host.addGuest(
      MatchInfo(
        matchId: id,
        gameId: gameId,
        opponent: gm.me,
        opponentName: names?[i + 1] ?? 'G$i',
        isHost: true,
      ),
    );
    final guest = RoomGuest(
      MatchInfo(
        matchId: id,
        gameId: gameId,
        opponent: hostMsg.me,
        opponentName: names?[0] ?? 'Host',
        isHost: false,
      ),
      factoryFor(gm),
    );
    guestRooms.add(guest.room);
  }
  for (var i = 0; i < 50 && host.connected.length < guests; i++) {
    await pump();
  }
  expect(host.connected.length, guests);
  expect(host.isFull, isTrue);
  final hostRoom = host.start(options: options);
  final rooms = await Future.wait(guestRooms)
      .timeout(const Duration(seconds: 5));
  return [hostRoom, ...rooms];
}
