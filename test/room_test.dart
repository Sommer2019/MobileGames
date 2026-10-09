import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/net/room.dart';
import 'package:mobile_games/core/net/matchmaker.dart';
import 'package:mobile_games/core/net/random_room.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

void main() {
  test('roster: seats, names and options reach all guests', () async {
    final rooms = await buildRoom(FakeRelayBus(), 3);
    expect(rooms.map((r) => r.mySeat), [0, 1, 2, 3]);
    for (final r in rooms) {
      expect(r.names, ['Host', 'G0', 'G1', 'G2']);
      expect(r.options['mode'], 'x');
      expect(r.size, 4);
    }
    expect(rooms[2].nameOf(2), 'Du');
  });

  test(
    'messages from every seat reach every other seat in host order',
    () async {
      final rooms = await buildRoom(FakeRelayBus(), 3);
      final received = [for (final _ in rooms) <String>[]];
      for (var i = 0; i < rooms.length; i++) {
        rooms[i].messages.listen(
          (m) => received[i].add('${m.seat}:${m.data['n']}'),
        );
      }
      rooms[1].send({'n': 'a'});
      await pump(200);
      rooms[0].send({'n': 'b'});
      await pump(200);
      rooms[3].send({'n': 'c'});
      await pump(300);
      expect(received[0], ['1:a', '3:c']);
      expect(received[1], ['0:b', '3:c']);
      expect(received[2], ['1:a', '0:b', '3:c']);
      expect(received[3], ['1:a', '0:b']);
    },
  );

  test('chat is shared and guests cannot spoof seats', () async {
    final rooms = await buildRoom(FakeRelayBus(), 2);
    rooms[2].sendChat('Hallo zusammen');
    await pump(300);
    for (final r in rooms) {
      expect(r.chat.single.text, 'Hallo zusammen');
      expect(r.chat.single.name, 'G1');
      expect(r.chat.single.seat, 2);
    }
  });

  test('chat spam is slowed down', () async {
    final rooms = await buildRoom(FakeRelayBus(), 1);
    final sent = [for (var i = 0; i < 20; i++) rooms[1].sendChat('Nochmal?')];
    expect(sent.where((ok) => ok), hasLength(5));
    await pump(300);
    expect(rooms[0].chat, hasLength(5));
    expect(rooms[1].chat, hasLength(5));
  });

  test('a player leaving is announced to everybody', () async {
    final rooms = await buildRoom(FakeRelayBus(), 2);
    await rooms[1].close();
    await pump(400);
    expect(rooms[0].leftPlayer, 'G0');
    expect(rooms[2].leftPlayer, 'G0');
  });

  test('random rooms: four searchers end up in one room of four', () async {
    final bus = FakeRelayBus();
    final searches = <RandomRoomSearch>[];
    final hostJoins = <String, List<MatchInfo>>{};
    final guestOf = <String, MatchInfo>{};
    for (var i = 0; i < 4; i++) {
      final m = newMessenger(bus);
      final s = RandomRoomSearch(
        m,
        gameId: 'connect_four',
        size: 4,
        nameProvider: () => 'P$i',
        lookTime: Duration(milliseconds: 100 + i * 10),
        advertInterval: const Duration(milliseconds: 60),
        handshakeTimeout: const Duration(milliseconds: 400),
      );
      s.events.listen((e) {
        switch (e) {
          case GuestJoined(:final match):
            hostJoins.putIfAbsent(m.me, () => []).add(match);
          case JoinedRoom(:final match):
            guestOf[m.me] = match;
          case HostingStarted():
            break;
        }
      });
      searches.add(s);
      s.start();
      await pump(5);
    }
    for (var i = 0; i < 100 && guestOf.length < 3; i++) {
      await pump();
    }
    expect(guestOf.length, 3);
    final host = guestOf.values.first.opponent;
    expect(guestOf.values.every((m) => m.opponent == host), isTrue);
    expect(hostJoins[host]!.length, 3);
    for (final s in searches) {
      s.cancel();
    }
  });

  test(
    'computer players: seats after the guests, moves sent by the host',
    () async {
      final bus = FakeRelayBus();
      final rooms = await buildRoom(bus, 1, bots: 2);
      final host = rooms[0], guest = rooms[1];
      expect(host.names, ['Host', 'G0', 'Computer 1', 'Computer 2']);
      expect(guest.botSeats, {2, 3});
      expect(host.botSeats, {2, 3});
      final got = <RoomMessage>[];
      guest.messages.listen(got.add);
      host.sendAs(3, {'t': 'move', 'x': 1});
      guest.sendAs(2, {'t': 'cheat'}); // only the host may move for bots
      for (var i = 0; i < 50 && got.isEmpty; i++) {
        await pump();
      }
      expect(got.single.seat, 3);
      expect(got.single.data['x'], 1);
    },
  );
}
