import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Randomness that follows from a seed: SHA-256 of "seed:counter", the same
/// on every device and platform. Games played with it can be replayed by
/// anybody from their recorded moves (see the leaderboard).
class SeededRandom implements Random {
  SeededRandom(this.seed);

  final String seed;
  int _counter = 0;
  List<int> _bytes = const [];
  int _pos = 0;

  int _byte() {
    if (_pos >= _bytes.length) {
      _bytes = sha256.convert(utf8.encode('$seed:${_counter++}')).bytes;
      _pos = 0;
    }
    return _bytes[_pos++];
  }

  // Arithmetic instead of bit shifts: on the web those work on signed 32-bit
  // numbers and would give other values than on phones.
  int _uint32() =>
      _byte() * 16777216 + _byte() * 65536 + _byte() * 256 + _byte();

  static const _range = 4294967296; // 2^32

  @override
  int nextInt(int max) {
    if (max <= 0 || max > _range) throw RangeError.range(max, 1, _range);
    // Rejection sampling keeps every value equally likely.
    if (max <= 256) {
      final limit = 256 - 256 % max;
      while (true) {
        final b = _byte();
        if (b < limit) return b % max;
      }
    }
    final limit = _range - _range % max;
    while (true) {
      final v = _uint32();
      if (v < limit) return v % max;
    }
  }

  @override
  bool nextBool() => _byte() & 1 == 1;

  @override
  double nextDouble() => _uint32() / _range;
}

/// Seeds of recorded games start with the player's public key, so nobody
/// can publish somebody else's good game as their own.
String newProofSeed(String pubkey) =>
    '$pubkey:${DateTime.now().microsecondsSinceEpoch}';

bool seedOwnedBy(String seed, String author) => seed.startsWith('$author:');

/// The seed and moves of a recorded game in a proof, or null if malformed.
(String, List<String>)? readProof(Object? j, {int maxMoves = 5000}) {
  if (j is! Map) return null;
  final s = j['s'], m = j['m'];
  if (s is! String || m is! List || m.length > maxMoves) return null;
  if (m.any((e) => e is! String)) return null;
  return (s, m.cast<String>().toList());
}
