import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/chat.dart';
import 'package:mobile_games/core/moderation.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

Future<void> pump([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Moderation.I.load();
  });

  test('messages of blocked players are dropped', () async {
    final bus = FakeRelayBus();
    final prefs = await SharedPreferences.getInstance();
    final a = KeyPair.generate(), b = KeyPair.generate();
    final chatA = ChatService(bus.client(), a, prefs: prefs);
    final chatB = ChatService(bus.client(), b, prefs: prefs);
    await chatA.start();
    await chatB.start();

    await chatA.send(b.publicKey, 'Hallo', myName: 'Anna');
    await pump();
    expect(chatB.messages(a.publicKey), hasLength(1));

    await Moderation.I.block(a.publicKey, 'Anna');
    await chatA.send(b.publicKey, 'Spam', myName: 'Anna');
    await chatA.sendSignal(b.publicKey, 'friendRequest', myName: 'Anna');
    final signals = <ChatSignal>[];
    chatB.signals.listen(signals.add);
    await pump();
    expect(chatB.messages(a.publicKey), hasLength(1));
    expect(signals, isEmpty);
  });

  test('the block list survives a restart and can be lifted', () async {
    final k = KeyPair.generate().publicKey;
    await Moderation.I.block(k, 'Max Mustermann');
    await Moderation.I.load();
    expect(Moderation.I.isBlocked(k), isTrue);
    expect(Moderation.I.blocked[k], 'Max Mustermann');
    await Moderation.I.unblock(k);
    await Moderation.I.load();
    expect(Moderation.I.isBlocked(k), isFalse);
  });

  test('a report names the player and quotes the messages', () {
    final k = KeyPair.generate().publicKey;
    final text = Moderation.reportText(
      name: 'Max',
      pubkey: k,
      messages: ['böse Nachricht'],
      reason: 'Beleidigung',
    );
    expect(text, contains('Max'));
    expect(text, contains(shortCodeFor(k)));
    expect(text, contains('> böse Nachricht'));
    expect(text, contains('Grund: Beleidigung'));
    // Without a configured address the report becomes a GitHub issue.
    final uri = Moderation.reportUri('Meldung: Max', text);
    expect(uri.host, 'github.com');
    expect(uri.queryParameters['body'], text);
  });
}
