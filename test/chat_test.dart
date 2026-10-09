import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/chat.dart';
import 'package:mobile_games/core/nostr/event.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

Future<void> pump([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('friends exchange messages, unread counts and persistence', () async {
    final bus = FakeRelayBus();
    final prefsA = await SharedPreferences.getInstance();
    final a = KeyPair.generate(), b = KeyPair.generate();
    final chatA = ChatService(bus.client(), a, prefs: prefsA);
    final chatB = ChatService(bus.client(), b, prefs: prefsA);
    await chatA.start();
    await chatB.start();
    final incoming = <IncomingChat>[];
    chatB.incoming.listen(incoming.add);

    await chatA.send(b.publicKey, 'Hallo Ben!', myName: 'Anna');
    await pump();
    expect(chatA.messages(b.publicKey).single.mine, isTrue);
    expect(chatB.messages(a.publicKey).single.text, 'Hallo Ben!');
    expect(chatB.messages(a.publicKey).single.mine, isFalse);
    expect(chatB.unread(a.publicKey), 1);
    expect(chatB.totalUnread, 1);
    expect(chatB.nameOf(a.publicKey), 'Anna');
    expect(incoming.single.senderName, 'Anna');

    chatB.openConversation = a.publicKey;
    await chatA.send(b.publicKey, 'Lust auf Schach?', myName: 'Anna');
    await pump();
    expect(chatB.unread(a.publicKey), 1, reason: 'open chat does not count');
    chatB.markRead(a.publicKey);
    expect(chatB.totalUnread, 0);
    expect(chatB.conversations, [a.publicKey]);
  });

  test('spam: sending is slowed down, floods are dropped', () async {
    final bus = FakeRelayBus();
    final prefs = await SharedPreferences.getInstance();
    final a = KeyPair.generate(), b = KeyPair.generate();
    final chatA = ChatService(bus.client(), a, prefs: prefs);
    final chatB = ChatService(bus.client(), b, prefs: prefs);
    await chatA.start();
    await chatB.start();

    final sent = [
      for (var i = 0; i < 8; i++)
        await chatA.send(b.publicKey, 'Gutes Spiel!', myName: 'A'),
    ];
    expect(sent, [...List.filled(5, true), ...List.filled(3, false)]);
    await pump();
    expect(chatB.messages(a.publicKey), hasLength(5));

    // A changed app skipping the limit: the receiver drops the flood.
    final c = KeyPair.generate();
    final client = bus.client();
    for (var i = 0; i < 30; i++) {
      await client.publish(
        NostrEvent.create(
          keys: c,
          kind: ChatService.kind,
          content: nip44Encrypt(
            c.privateKey,
            b.publicKey,
            jsonEncode({'mg': 1, 'text': 'Nochmal? $i', 'name': 'C'}),
          ),
          tags: [
            ['p', b.publicKey],
          ],
        ),
      );
    }
    await pump();
    expect(chatB.messages(c.publicKey), hasLength(5));
  });

  test('history survives a restart', () async {
    final bus = FakeRelayBus();
    final prefs = await SharedPreferences.getInstance();
    final a = KeyPair.generate(), b = KeyPair.generate();
    final chatA = ChatService(bus.client(), a, prefs: prefs);
    await chatA.start();
    await chatA.send(b.publicKey, 'gespeichert', myName: 'A');
    final restarted = ChatService(bus.client(), a, prefs: prefs);
    await restarted.start();
    expect(restarted.messages(b.publicKey).single.text, 'gespeichert');
  });

  test('messages cannot be read by third parties', () async {
    final bus = FakeRelayBus();
    final prefs = await SharedPreferences.getInstance();
    final a = KeyPair.generate(), b = KeyPair.generate();
    final chatA = ChatService(bus.client(), a, prefs: prefs);
    await chatA.start();
    await chatA.send(b.publicKey, 'geheim', myName: 'A');
    final event = bus.published.last;
    expect(event.kind, 4);
    expect(event.content, isNot(contains('geheim')));
  });
}
