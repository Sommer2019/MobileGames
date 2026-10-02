import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the account key across reinstalls, without a server:
///
/// * Android: the key is derived from the app's ANDROID_ID. That ID stays the
///   same for this app on this phone as long as the APK is signed with the
///   same key (see README: release signing).
/// * iOS: the key is also kept in the Keychain, which survives deleting the
///   app (as long as it is signed by the same team).
class DeviceIdentity {
  DeviceIdentity._();

  static const _channel = MethodChannel('mobilegames/device');
  static const _storage = FlutterSecureStorage();
  static const _key = 'account.privateKey';

  static final bool _testing =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// The key from a previous installation on this device, or null.
  static Future<String?> recover() async {
    if (_testing || kIsWeb) return null;
    try {
      if (Platform.isIOS) return await _storage.read(key: _key);
      if (Platform.isAndroid) {
        final id = await _channel.invokeMethod<String>('androidId');
        if (id == null || id.isEmpty) return null;
        return keyFromDeviceId(id);
      }
    } catch (_) {}
    return null;
  }

  /// Stores [privateKey] where it survives a reinstall (iOS Keychain).
  static Future<void> remember(String privateKey) async {
    if (_testing || kIsWeb || !Platform.isIOS) return;
    try {
      await _storage.write(
        key: _key,
        value: privateKey,
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );
    } catch (_) {}
  }

  /// A private key (64 hex chars) derived from a device id.
  static String keyFromDeviceId(String id) =>
      sha256.convert(utf8.encode('mobilegames-account-v1:$id')).toString();
}
