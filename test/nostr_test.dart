import 'package:convert/convert.dart';

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

  test('nip44 matches the official test vector', () {
    const sec1 =
        '0000000000000000000000000000000000000000000000000000000000000001';
    const sec2 =
        '0000000000000000000000000000000000000000000000000000000000000002';
    final pub2 = KeyPair(sec2).publicKey;
    expect(
      hex.encode(nip44ConversationKey(sec1, pub2)),
      'c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d',
    );
    final nonce = List<int>.filled(32, 0)..[31] = 1;
    // Version 2, the nonce, then ciphertext and MAC of the official vector.
    final payload = base64.encode([
      2,
      ...nonce,
      ...base64
          .decode(
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB'
            'ee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNa'
            'CXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb',
          )
          .sublist(33),
    ]);
    expect(nip44Encrypt(sec1, pub2, 'a', null, nonce), payload);
    expect(nip44Decrypt(sec2, KeyPair(sec1).publicKey, payload), 'a');
  });

  test('nip44 padding lengths', () {
    expect(nip44PaddedLength(1), 32);
    expect(nip44PaddedLength(32), 32);
    expect(nip44PaddedLength(33), 64);
    expect(nip44PaddedLength(37), 64);
    expect(nip44PaddedLength(45), 64);
    expect(nip44PaddedLength(49), 64);
    expect(nip44PaddedLength(64), 64);
    expect(nip44PaddedLength(65), 96);
    expect(nip44PaddedLength(100), 128);
    expect(nip44PaddedLength(111), 128);
    expect(nip44PaddedLength(200), 224);
    expect(nip44PaddedLength(250), 256);
    expect(nip44PaddedLength(320), 320);
    expect(nip44PaddedLength(383), 384);
    expect(nip44PaddedLength(384), 384);
    expect(nip44PaddedLength(400), 448);
    expect(nip44PaddedLength(500), 512);
    expect(nip44PaddedLength(512), 512);
    expect(nip44PaddedLength(515), 640);
    expect(nip44PaddedLength(700), 768);
    expect(nip44PaddedLength(800), 896);
    expect(nip44PaddedLength(900), 1024);
    expect(nip44PaddedLength(1020), 1024);
    expect(nip44PaddedLength(65536), 65536);
  });

  test('nip44 roundtrip; tampering and wrong keys are rejected', () {
    final a = KeyPair.generate();
    final b = KeyPair.generate();
    const text = '{"type":"invite","ä":1}';
    final cipher = nip44Encrypt(a.privateKey, b.publicKey, text);
    expect(nip44Decrypt(b.privateKey, a.publicKey, cipher), text);
    // A different nonce every time.
    expect(nip44Encrypt(a.privateKey, b.publicKey, text), isNot(cipher));
    // Long messages work too.
    final long = 'x' * 60000;
    expect(
      nip44Decrypt(
        b.privateKey,
        a.publicKey,
        nip44Encrypt(a.privateKey, b.publicKey, long),
      ),
      long,
    );
    // One flipped bit: the MAC catches it.
    final bytes = base64.decode(cipher);
    bytes[40] ^= 1;
    expect(
      () => nip44Decrypt(b.privateKey, a.publicKey, base64.encode(bytes)),
      throwsFormatException,
    );
    final c = KeyPair.generate();
    expect(
      () => nip44Decrypt(c.privateKey, a.publicKey, cipher),
      throwsFormatException,
    );
  });
}
