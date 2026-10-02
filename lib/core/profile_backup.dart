import 'dart:async';
import 'dart:convert';

import 'account.dart';
import 'names.dart';
import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';

/// Keeps name and friend list on the relays, encrypted so only the owner of
/// the key can read them (NIP-04 to oneself, NIP-78 app data). After a
/// reinstall with the same key (see [DeviceIdentity]) they come back.
class ProfileBackup {
  ProfileBackup(this.client, this.account);

  static const kind = 30078;
  static const _d = 'mobilegames-profile';

  final NostrClient client;
  final Account account;
  Timer? _debounce;

  /// Saves the profile a little later (several changes, one event).
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), publish);
  }

  Future<void> publish() async {
    final me = account.keys;
    final plain = jsonEncode({
      'name': account.name,
      'friends': [for (final f in account.friends) f.toJson()],
    });
    await client.publish(
      NostrEvent.create(
        keys: me,
        kind: kind,
        content: nip04Encrypt(me.privateKey, me.publicKey, plain),
        tags: [
          ['d', _d],
        ],
      ),
    );
  }

  /// Loads the saved profile and merges it in: missing friends are added,
  /// the name is taken over if ours is still the default one.
  Future<bool> restore({Duration timeout = const Duration(seconds: 6)}) async {
    final me = account.keys;
    NostrEvent? latest;
    final sub = client
        .subscribe({
          'kinds': [kind],
          'authors': [me.publicKey],
          '#d': [_d],
        })
        .listen((e) {
          if (e.pubkey != me.publicKey) return;
          if (latest == null || e.createdAt > latest!.createdAt) latest = e;
        });
    await Future<void>.delayed(timeout);
    await sub.cancel();
    final e = latest;
    if (e == null) return false;
    try {
      final j = jsonDecode(
        nip04Decrypt(me.privateKey, me.publicKey, e.content),
      ) as Map<String, dynamic>;
      var changed = false;
      final name = cleanNameOrNull(j['name']);
      if (name != null && account.name.startsWith('Spieler ')) {
        await account.setName(name);
        changed = true;
      }
      for (final f in j['friends'] as List? ?? const []) {
        final friend = Friend.fromJson(Map<String, dynamic>.from(f as Map));
        if (account.friend(friend.pubkey) == null) {
          await account.addFriend(friend.pubkey, name: friend.name);
          changed = true;
        }
      }
      return changed;
    } catch (_) {
      return false;
    }
  }
}
