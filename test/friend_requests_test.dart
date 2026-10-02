import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/chat.dart';
import 'package:mobile_games/core/friend_requests.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

class Player {
  late Account account;
  late ChatService chat;
  late FriendRequests requests;
  final requestsSeen = <String>[];
  final accepted = <String>[];

  static Future<Player> create(
    FakeRelayBus bus,
    String prefix,
    String name,
  ) async {
    final p = Player();
    p.account = await Account.load(prefix: prefix);
    await p.account.setName(name);
    p.chat = ChatService(bus.client(), p.account.keys);
    p.requests = FriendRequests(p.account, p.chat);
    await p.requests.start();
    await p.chat.start();
    p.requests.incoming.listen(p.requestsSeen.add);
    p.requests.accepted.listen(p.accepted.add);
    return p;
  }
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('adding a friend sends a request; accepting makes it mutual', () async {
    final bus = FakeRelayBus();
    final anna = await Player.create(bus, 'a', 'Anna');
    final ben = await Player.create(bus, 'b', 'Ben');

    expect(await anna.requests.addByCode(ben.account.friendCode), isNull);
    await pump();
    expect(anna.account.friend(ben.account.keys.publicKey), isNotNull);
    expect(ben.requestsSeen, [anna.account.keys.publicKey]);
    expect(ben.requests.pending.values, ['Anna']);
    expect(ben.account.friends, isEmpty);

    await ben.requests.acceptRequest(anna.account.keys.publicKey);
    await pump();
    expect(ben.account.friend(anna.account.keys.publicKey)?.name, 'Anna');
    expect(ben.requests.pending, isEmpty);
    expect(anna.accepted, [ben.account.keys.publicKey]);
    expect(anna.account.friend(ben.account.keys.publicKey)?.name, 'Ben');
  });

  test(
    'declined requests do not come back; mutual adding needs no prompt',
    () async {
      final bus = FakeRelayBus();
      final anna = await Player.create(bus, 'a', 'Anna');
      final ben = await Player.create(bus, 'b', 'Ben');
      await anna.requests.addByCode(ben.account.friendCode);
      await pump();
      await ben.requests.declineRequest(anna.account.keys.publicKey);
      // Anna removes and re-adds Ben: no new request popup for Ben.
      await anna.account.removeFriend(ben.account.keys.publicKey);
      await anna.requests.addByCode(ben.account.friendCode);
      await pump();
      expect(ben.requestsSeen.length, 1);
      expect(ben.requests.pending, isEmpty);

      // Carla adds Dave, Dave adds Carla himself instead of tapping accept.
      final carla = await Player.create(bus, 'c', 'Carla');
      final dave = await Player.create(bus, 'd', 'Dave');
      await carla.requests.addByCode(dave.account.friendCode);
      await pump();
      await dave.requests.addByCode(carla.account.friendCode);
      await pump();
      expect(dave.requests.pending, isEmpty);
      expect(carla.accepted, [dave.account.keys.publicKey]);
    },
  );

  test('requests are not shown as chat messages', () async {
    final bus = FakeRelayBus();
    final anna = await Player.create(bus, 'a', 'Anna');
    final ben = await Player.create(bus, 'b', 'Ben');
    await anna.requests.addByCode(ben.account.friendCode);
    await pump();
    expect(ben.chat.conversations, isEmpty);
    expect(ben.chat.totalUnread, 0);
  });
}
