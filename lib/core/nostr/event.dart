import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

import 'keys.dart';

/// A signed Nostr event (NIP-01).
class NostrEvent {
  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.create({
    required KeyPair keys,
    required int kind,
    required String content,
    List<List<String>> tags = const [],
    DateTime? createdAt,
  }) {
    final ts = (createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final id = computeId(keys.publicKey, ts, kind, tags, content);
    final sig = bip340.sign(keys.privateKey, id, randomHex(32));
    return NostrEvent(
      id: id,
      pubkey: keys.publicKey,
      createdAt: ts,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  factory NostrEvent.fromJson(Map<String, dynamic> j) => NostrEvent(
    id: j['id'] as String,
    pubkey: j['pubkey'] as String,
    createdAt: j['created_at'] as int,
    kind: j['kind'] as int,
    tags: [
      for (final t in j['tags'] as List)
        [for (final s in t as List) s.toString()],
    ],
    content: j['content'] as String,
    sig: j['sig'] as String,
  );

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  static String computeId(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) {
    final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }

  /// Checks id and signature.
  bool get isValid {
    if (computeId(pubkey, createdAt, kind, tags, content) != id) return false;
    try {
      return bip340.verify(pubkey, id, sig);
    } catch (_) {
      return false;
    }
  }

  String? tag(String name) {
    for (final t in tags) {
      if (t.length >= 2 && t[0] == name) return t[1];
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };
}
