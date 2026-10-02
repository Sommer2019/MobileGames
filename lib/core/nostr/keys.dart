import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// secp256k1 key helpers (BIP-340 / Nostr compatible).
class KeyPair {
  KeyPair(this.privateKey) : publicKey = bip340.getPublicKey(privateKey);

  factory KeyPair.generate([Random? random]) => KeyPair(randomHex(32, random));

  final String privateKey;
  final String publicKey;
}

String randomHex(int bytes, [Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(bytes, (_) => r.nextInt(256));
  // The private key must be in [1, n-1]; a random 32 byte value is
  // practically always valid, but guard against the zero key anyway.
  if (b.every((x) => x == 0)) b[31] = 1;
  return hex.encode(b);
}

final ECDomainParameters _secp256k1 = ECCurve_secp256k1();

ECPoint _liftX(String xOnlyPubKey) {
  // Even-y point for an x-only public key ("02" prefix).
  final compressed = Uint8List.fromList([0x02, ...hex.decode(xOnlyPubKey)]);
  return _secp256k1.curve.decodePoint(compressed)!;
}

/// ECDH shared secret (x coordinate) as used by NIP-04.
Uint8List sharedSecret(String privateKey, String otherPublicKey) {
  final d = BigInt.parse(privateKey, radix: 16);
  final p = (_liftX(otherPublicKey) * d)!;
  final x = p.x!.toBigInteger()!.toRadixString(16).padLeft(64, '0');
  return Uint8List.fromList(hex.decode(x));
}

/// NIP-04 encryption: AES-256-CBC with the ECDH shared x coordinate as key.
String nip04Encrypt(
  String privateKey,
  String otherPublicKey,
  String plain, [
  Random? random,
]) {
  final key = sharedSecret(privateKey, otherPublicKey);
  final r = random ?? Random.secure();
  final iv = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
  final out = cipher.process(Uint8List.fromList(utf8.encode(plain)));
  return '${base64.encode(out)}?iv=${base64.encode(iv)}';
}

String nip04Decrypt(String privateKey, String otherPublicKey, String payload) {
  final parts = payload.split('?iv=');
  if (parts.length != 2) throw const FormatException('invalid nip04 payload');
  final key = sharedSecret(privateKey, otherPublicKey);
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), base64.decode(parts[1])),
          null,
        ),
      );
  return utf8.decode(cipher.process(base64.decode(parts[0])));
}

// ---------------------------------------------------------------------------
// bech32 (NIP-19 "npub") so friend codes are copy/paste friendly.

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

int _polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final b = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if ((b >> i) & 1 == 1) chk ^= gen[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) => [
  ...hrp.codeUnits.map((c) => c >> 5),
  0,
  ...hrp.codeUnits.map((c) => c & 31),
];

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var acc = 0, bits = 0;
  final out = <int>[];
  final maxv = (1 << to) - 1;
  for (final value in data) {
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxv);
    }
  }
  if (pad) {
    if (bits > 0) out.add((acc << (to - bits)) & maxv);
  } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
    throw const FormatException('invalid padding');
  }
  return out;
}

String bech32Encode(String hrp, List<int> bytes) {
  final data = _convertBits(bytes, 8, 5, true);
  final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
  final mod = _polymod(values) ^ 1;
  final checksum = List.generate(6, (i) => (mod >> (5 * (5 - i))) & 31);
  return '${hrp}1${[...data, ...checksum].map((d) => _charset[d]).join()}';
}

(String, List<int>) bech32Decode(String input) {
  final s = input.trim().toLowerCase();
  final pos = s.lastIndexOf('1');
  if (pos < 1 || pos + 7 > s.length) {
    throw const FormatException('invalid bech32');
  }
  final hrp = s.substring(0, pos);
  final data = <int>[];
  for (final ch in s.substring(pos + 1).split('')) {
    final v = _charset.indexOf(ch);
    if (v < 0) throw const FormatException('invalid bech32 character');
    data.add(v);
  }
  if (_polymod([..._hrpExpand(hrp), ...data]) != 1) {
    throw const FormatException('invalid bech32 checksum');
  }
  return (hrp, _convertBits(data.sublist(0, data.length - 6), 5, 8, false));
}

String pubKeyToNpub(String publicKey) =>
    bech32Encode('npub', hex.decode(publicKey));

/// Accepts an npub or a 64 char hex key. Returns the hex public key or null.
String? parseFriendCode(String code) {
  final c = code.trim();
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(c)) return c.toLowerCase();
  try {
    final (hrp, bytes) = bech32Decode(c);
    if (hrp != 'npub' || bytes.length != 32) return null;
    return hex.encode(bytes);
  } on FormatException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Short friend codes: 10 characters of Crockford base32 (50 bits) taken from
// sha256(public key). They are resolved through a signed Nostr event; the
// public key in that event must hash to the code, so it cannot be faked.

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String shortCodeFor(String publicKey) {
  final digest = sha256.convert(hex.decode(publicKey)).bytes;
  var bits = 0, value = 0;
  final out = StringBuffer();
  for (final byte in digest) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5 && out.length < 10) {
      bits -= 5;
      out.write(_crockford[(value >> bits) & 31]);
    }
    value &= (1 << bits) - 1;
    if (out.length >= 10) break;
  }
  return out.toString();
}

/// "K7Q2M9XW4P" -> "K7Q2M-9XW4P"
String formatShortCode(String code) =>
    code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

/// Normalises user input to a 10 character short code, or null.
String? parseShortCode(String input) {
  final cleaned = input
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1')
      .replaceAll('U', 'V');
  if (cleaned.length != 10) return null;
  for (final ch in cleaned.split('')) {
    if (!_crockford.contains(ch)) return null;
  }
  return cleaned;
}
