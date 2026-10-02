import 'dart:async';
import 'dart:convert';

import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';

/// Publishes our short friend code and resolves codes of others.
///
/// The code is announced as a replaceable app-data event (NIP-78, kind
/// 30078). Relays keep it, so friends can look the code up any time.
class FriendCodes {
  FriendCodes(this.client, this.keys);

  static const kind = 30078;
  static const _d = 'mobilegames-code';

  final NostrClient client;
  final KeyPair keys;

  String get myCode => shortCodeFor(keys.publicKey);

  Future<void> publish(String name) => client.publish(
    NostrEvent.create(
      keys: keys,
      kind: kind,
      content: jsonEncode({'name': name}),
      tags: [
        ['d', _d],
        ['c', myCode],
      ],
    ),
  );

  /// Looks up a short code. Returns (public key, name) or null.
  Future<(String, String?)?> resolve(
    String code, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final completer = Completer<(String, String?)?>();
    late final StreamSubscription<NostrEvent> sub;
    sub = client
        .subscribe({
          'kinds': [kind],
          '#c': [code],
        })
        .listen((e) {
          // Only accept a key that really hashes to the code.
          if (shortCodeFor(e.pubkey) != code || completer.isCompleted) return;
          String? name;
          try {
            name = (jsonDecode(e.content) as Map)['name'] as String?;
          } catch (_) {}
          completer.complete((e.pubkey, name));
        });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }
}
