import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/nostr/event.dart';
import 'package:mobile_games/core/nostr/keys.dart';

void main() {
  test('npub encoding matches NIP-19 test vector', () {
    const hexKey =
        '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
    const npub =
        'npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6';
    expect(pubKeyToNpub(hexKey), npub);
    expect(parseFriendCode(npub), hexKey);
    expect(parseFriendCode(hexKey.toUpperCase()), hexKey);
    expect(parseFriendCode('npub1invalid'), isNull);
    expect(parseFriendCode('hallo'), isNull);
  });

  test('signed events verify and tampering is detected', () {
    final keys = KeyPair.generate();
    final e = NostrEvent.create(
      keys: keys,
      kind: 25911,
      content: 'hi',
      tags: [
        ['p', keys.publicKey],
      ],
    );
    expect(e.isValid, isTrue);
    final roundTrip = NostrEvent.fromJson(jsonDecode(jsonEncode(e.toJson())));
    expect(roundTrip.isValid, isTrue);
    expect(roundTrip.tag('p'), keys.publicKey);
    final forged = NostrEvent(
      id: e.id,
      pubkey: e.pubkey,
      createdAt: e.createdAt,
      kind: e.kind,
      tags: e.tags,
      content: 'evil',
      sig: e.sig,
    );
    expect(forged.isValid, isFalse);
  });

  test('nip04 roundtrip between two parties', () {
    final a = KeyPair.generate();
    final b = KeyPair.generate();
    expect(
      sharedSecret(a.privateKey, b.publicKey),
      sharedSecret(b.privateKey, a.publicKey),
    );
    final cipher = nip04Encrypt(
      a.privateKey,
      b.publicKey,
      '{"type":"invite","ä":1}',
    );
    expect(cipher, contains('?iv='));
    expect(
      nip04Decrypt(b.privateKey, a.publicKey, cipher),
      '{"type":"invite","ä":1}',
    );
    final c = KeyPair.generate();
    String? wrong;
    try {
      wrong = nip04Decrypt(c.privateKey, a.publicKey, cipher);
    } catch (_) {
      wrong = null;
    }
    expect(wrong, isNot('{"type":"invite","ä":1}'));
  });
}
