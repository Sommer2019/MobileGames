import 'dart:async';

import 'package:convert/convert.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity.dart';
import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';

/// Moving the account to another phone.
///
/// The old phone shows its secret key as a code (QR or text); the new phone
/// takes it over. Name and friends then come back from the encrypted
/// profile backup on the relays.
///
/// Android derives the key from the device id, so a reinstall on the new
/// phone would bring back the phone's own key instead of the taken-over
/// one. To survive that, the new phone leaves a "redirect" on the relays:
/// the taken-over key, encrypted with and signed by the device key. Only
/// this device can read it.
class AccountTransfer {
  AccountTransfer._();

  static const kind = 30078;
  static const _d = 'mobilegames-redirect';
  static const _hrp = 'mgkonto';

  /// The code that carries [privateKey] to another phone.
  static String codeFor(String privateKey) =>
      bech32Encode(_hrp, hex.decode(privateKey));

  /// The private key in a transfer code, or null if it isn't one.
  static String? parse(String code) {
    var c = code.trim();
    if (c.startsWith('mobilegames://konto/')) {
      c = c.substring('mobilegames://konto/'.length);
    }
    try {
      final (hrp, bytes) = bech32Decode(c);
      if (hrp != _hrp || bytes.length != 32) return null;
      final key = hex.encode(bytes);
      KeyPair(key); // throws for an invalid key
      return key;
    } on Object {
      return null;
    }
  }

  /// Content of the QR code.
  static String qrPayload(String privateKey) =>
      'mobilegames://konto/${codeFor(privateKey)}';

  /// Makes [privateKey] the account of this device. Takes effect when the
  /// app starts the next time.
  static Future<void> adopt(
    String privateKey, {
    NostrClient? client,
    String prefix = 'account',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$prefix.privateKey', privateKey);
    // The friend list of the account so far would mix with the new one.
    await prefs.remove('$prefix.friends');
    await prefs.remove('$prefix.name');
    await DeviceIdentity.remember(privateKey);
    final device = await DeviceIdentity.androidKey();
    if (device != null && client != null && device != privateKey) {
      await publishRedirect(client, device, privateKey);
    }
  }

  /// Leaves the encrypted pointer from the device key to [target].
  static Future<void> publishRedirect(
    NostrClient client,
    String deviceKey,
    String target,
  ) async {
    final keys = KeyPair(deviceKey);
    await client.publish(
      NostrEvent.create(
        keys: keys,
        kind: kind,
        content: nip44Encrypt(deviceKey, keys.publicKey, target),
        tags: [
          ['d', _d],
        ],
      ),
    );
  }

  /// Follows a redirect left by [deviceKey], or returns [deviceKey].
  static Future<String> resolve(
    NostrClient client,
    String deviceKey, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final keys = KeyPair(deviceKey);
    NostrEvent? latest;
    final found = Completer<void>();
    final sub = client
        .subscribe({
          'kinds': [kind],
          'authors': [keys.publicKey],
          '#d': [_d],
        })
        .listen((e) {
          if (e.pubkey != keys.publicKey) return;
          if (latest == null || e.createdAt > latest!.createdAt) latest = e;
          if (!found.isCompleted) found.complete();
        });
    // The first answer is usually the only one; give others a moment.
    await found.future.timeout(timeout, onTimeout: () {});
    if (latest != null) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await sub.cancel();
    final e = latest;
    if (e == null) return deviceKey;
    try {
      final target = nip44Decrypt(deviceKey, keys.publicKey, e.content);
      KeyPair(target);
      return target;
    } on Object {
      return deviceKey;
    }
  }
}
