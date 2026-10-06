import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/chat.dart';
import 'package:mobile_games/core/moderation.dart';
import 'package:mobile_games/core/moderation_sync.dart';
import 'package:mobile_games/core/net/messenger.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

Future<void> pump([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeRelayBus bus;
  late KeyPair admin, player, troll;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Moderation.I.load();
    await Moderation.I.setBanned({});
    bus = FakeRelayBus();
    admin = KeyPair.generate();
    player = KeyPair.generate();
    troll = KeyPair.generate();
  });

  ModerationSync sync(KeyPair k) =>
      ModerationSync(bus.client(), k, admins: [admin.publicKey]);

  test('reports reach only the admin, encrypted', () async {
    final a = sync(admin), p = sync(player), other = sync(troll);
    await a.start();
    await p.start();
    await other.start();
    expect(a.isAdmin, isTrue);
    expect(p.isAdmin, isFalse);

    await p.report(
      name: 'Troll',
      pubkey: troll.publicKey,
      messages: ['böse'],
      reason: 'Beleidigung',
      myName: 'Anna',
    );
    await pump();
    expect(a.openReports, hasLength(1));
    final r = a.openReports.single;
    expect(r.pubkey, troll.publicKey);
    expect(r.fromName, 'Anna');
    expect(r.reason, 'Beleidigung');
    expect(r.messages, ['böse']);
    expect(other.openReports, isEmpty);
    expect(bus.published.last.content, isNot(contains('böse')));

    await a.dismiss(r);
    expect(a.openReports, isEmpty);
  });

  test('a ban from the admin silences the player for everyone', () async {
    final a = sync(admin), p = sync(player);
    await a.start();
    await p.start();
    final prefs = await SharedPreferences.getInstance();
    final chatP = ChatService(bus.client(), player, prefs: prefs);
    await chatP.start();
    final trollChat = ChatService(bus.client(), troll, prefs: prefs);
    await trollChat.start();

    await a.setBan(troll.publicKey, 'Troll', banned: true);
    await pump();
    expect(Moderation.I.isBanned(troll.publicKey), isTrue);
    expect(Moderation.I.isBlocked(troll.publicKey), isTrue);
    expect(Moderation.I.blocked, isEmpty);

    await trollChat.send(player.publicKey, 'Spam', myName: 'Troll');
    final direct = <DirectMessage>[];
    final messenger = Messenger(bus.client(), player)..start();
    messenger.messages.listen(direct.add);
    await Messenger(
      bus.client(),
      troll,
    ).send(player.publicKey, {'type': 'invite'});
    await pump();
    expect(chatP.messages(troll.publicKey), isEmpty);
    expect(direct, isEmpty);

    // Reports about banned players are done.
    await p.report(
      name: 'Troll',
      pubkey: troll.publicKey,
      messages: [],
      myName: 'Anna',
    );
    await pump();
    expect(a.openReports, isEmpty);

    await a.setBan(troll.publicKey, 'Troll', banned: false);
    await pump();
    expect(Moderation.I.isBanned(troll.publicKey), isFalse);
  });

  test('ban lists of others than the admins are ignored', () async {
    final fake = ModerationSync(bus.client(), troll, admins: [troll.publicKey]);
    await fake.start();
    await fake.setBan(player.publicKey, 'Anna', banned: true);
    final p = sync(player);
    await Moderation.I.setBanned({});
    await p.start();
    await pump();
    expect(Moderation.I.isBanned(player.publicKey), isFalse);
  });

  test('the ban list survives a restart, admins cannot be banned', () async {
    await Moderation.I.setBanned({
      troll.publicKey: 'Troll',
      admin.publicKey: 'Admin',
    });
    final saved = Moderation.admins;
    Moderation.admins = [admin.publicKey];
    addTearDown(() => Moderation.admins = saved);
    await Moderation.I.load();
    expect(Moderation.I.isBanned(troll.publicKey), isTrue);
    expect(Moderation.I.isBanned(admin.publicKey), isFalse);
  });

  test('admin keys are parsed from the build setting', () {
    final k = KeyPair.generate().publicKey;
    expect(Moderation.parseAdmins(''), isEmpty);
    expect(Moderation.parseAdmins('$k, nonsense ,${k.toUpperCase()}'), [k, k]);
  });
}
