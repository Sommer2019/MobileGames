import 'dart:async';
import 'dart:convert';

import '../nostr/event.dart';
import '../nostr/keys.dart';
import '../nostr/relay_pool.dart';

/// Ephemeral event kinds (20000-29999 are not stored by relays).
class Kinds {
  static const seek = 25910;
  static const direct = 25911;
  static const presence = 25912;
}

class DirectMessage {
  DirectMessage(this.from, this.data);
  final String from;
  final Map<String, dynamic> data;
  String get type => data['type'] as String? ?? '';
}

/// End-to-end encrypted (NIP-04) JSON messages between two players,
/// transported through public Nostr relays.
class Messenger {
  Messenger(this.client, this.keys);

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
    if (e.pubkey == me) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((now - e.createdAt).abs() > 120) return;
    try {
      final plain = nip04Decrypt(keys.privateKey, e.pubkey, e.content);
      final data = jsonDecode(plain);
      if (data is Map<String, dynamic>) {
        _controller.add(DirectMessage(e.pubkey, data));
      }
    } catch (_) {
      // Not for us or corrupted.
    }
  }

  Future<void> send(String to, Map<String, dynamic> data) {
    final content = nip04Encrypt(keys.privateKey, to, jsonEncode(data));
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
