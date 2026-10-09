import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../moderation.dart';
import '../nostr/event.dart';
import '../nostr/keys.dart';
import '../nostr/relay_pool.dart';

/// Ephemeral event kinds (20000-29999 are not stored by relays).
class Kinds {
  static const seek = 25910;
  static const direct = 25911;
  static const presence = 25912;

  /// Connection test: a message to oneself (not a presence).
  static const ping = 25913;
}

class DirectMessage {
  DirectMessage(this.from, this.data);
  final String from;
  final Map<String, dynamic> data;
  String get type => data['type'] as String? ?? '';
}

/// End-to-end encrypted (NIP-44) JSON messages between two players,
/// transported through public Nostr relays.
///
/// NIP-44 carries at most 64 KB and relays limit event sizes, so bigger
/// messages are split into pieces that are encrypted one by one and put
/// back together by the receiver.
class Messenger {
  Messenger(this.client, this.keys);

  /// Largest message (UTF-8 bytes) sent in one event; one piece of a split
  /// message carries this many bytes, too.
  static const maxPlain = 24000;

  /// Pieces of an incomplete message are dropped after this time.
  static const pieceTimeout = Duration(seconds: 60);

  final _pieces = <String, _Pieces>{};
  final _random = Random.secure();

  final NostrClient client;
  final KeyPair keys;
  final _controller = StreamController<DirectMessage>.broadcast();
  StreamSubscription<NostrEvent>? _sub;

  String get me => keys.publicKey;
  Stream<DirectMessage> get messages => _controller.stream;

  void start() {
    if (_sub != null) return;
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
    _sub = client
        .subscribe({
          'kinds': [Kinds.direct],
          '#p': [me],
          'since': since,
        })
        .listen(_onEvent);
  }

  void _onEvent(NostrEvent e) {
    if (e.pubkey == me || Moderation.I.isBlocked(e.pubkey)) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((now - e.createdAt).abs() > 120) return;
    try {
      final plain = nip44Decrypt(keys.privateKey, e.pubkey, e.content);
      final data = jsonDecode(plain);
      if (data is! Map<String, dynamic>) return;
      if (data['type'] == '_part') {
        _onPiece(e.pubkey, data);
      } else {
        _controller.add(DirectMessage(e.pubkey, data));
      }
    } catch (_) {
      // Not for us or corrupted.
    }
  }

  void _onPiece(String from, Map<String, dynamic> data) {
    final id = data['id'], i = data['i'], n = data['n'], d = data['d'];
    if (id is! String || i is! int || n is! int || d is! String) return;
    if (n < 2 || n > 1000 || i < 0 || i >= n) return;
    final now = DateTime.now();
    _pieces.removeWhere((_, p) => now.difference(p.started) > pieceTimeout);
    final key = '$from:$id';
    final p = _pieces.putIfAbsent(key, () => _Pieces(n, now));
    if (p.parts.length != n) return;
    p.parts[i] = base64Decode(d);
    if (p.parts.any((part) => part == null)) return;
    _pieces.remove(key);
    final bytes = [for (final part in p.parts) ...part!];
    final whole = jsonDecode(utf8.decode(bytes));
    if (whole is Map<String, dynamic>) {
      _controller.add(DirectMessage(from, whole));
    }
  }

  Future<void> send(String to, Map<String, dynamic> data) async {
    final bytes = utf8.encode(jsonEncode(data));
    if (bytes.length <= maxPlain) {
      return _publish(to, jsonEncode(data));
    }
    final n = (bytes.length + maxPlain - 1) ~/ maxPlain;
    final id = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    for (var i = 0; i < n; i++) {
      final end = min((i + 1) * maxPlain, bytes.length);
      await _publish(
        to,
        jsonEncode({
          'type': '_part',
          'id': id,
          'i': i,
          'n': n,
          'd': base64Encode(bytes.sublist(i * maxPlain, end)),
        }),
      );
    }
  }

  Future<void> _publish(String to, String plain) {
    final String content;
    try {
      content = nip44Encrypt(keys.privateKey, to, plain);
    } on FormatException catch (e) {
      debugPrint('Message to $to not sent: $e');
      return Future.value();
    }
    return client.publish(
      NostrEvent.create(
        keys: keys,
        kind: Kinds.direct,
        content: content,
        tags: [
          ['p', to],
        ],
      ),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// The pieces of a split message received so far.
class _Pieces {
  _Pieces(int n, this.started) : parts = List.filled(n, null);
  final List<List<int>?> parts;
  final DateTime started;
}
