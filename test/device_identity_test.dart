import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/device_identity.dart';
import 'package:mobile_games/core/profile_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

void main() {
  test('a reinstall on the same device gets the same account back', () async {
    final key = DeviceIdentity.keyFromDeviceId('a1b2c3d4e5f60718');
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(DeviceIdentity.keyFromDeviceId('a1b2c3d4e5f60718'), key);
    expect(DeviceIdentity.keyFromDeviceId('other'), isNot(key));

    SharedPreferences.setMockInitialValues({});
    final first = await Account.load(recover: () async => key);
    // "Uninstall": app data is gone.
    SharedPreferences.setMockInitialValues({});
    final again = await Account.load(recover: () async => key);
    expect(again.keys.publicKey, first.keys.publicKey);

    // Without a device key a new random account is created.
    SharedPreferences.setMockInitialValues({});
    final other = await Account.load(recover: () async => null);
    expect(other.keys.publicKey, isNot(first.keys.publicKey));
  });

  test('name and friends come back from the encrypted backup', () async {
    final bus = FakeRelayBus();
    final key = DeviceIdentity.keyFromDeviceId('phone');
    SharedPreferences.setMockInitialValues({});
    final friend = await Account.load(prefix: 'friend');
    final a = await Account.load(prefix: 'me', recover: () async => key);
    await a.setName('Robin');
    await a.addFriend(friend.keys.publicKey, name: 'Anna');
    await ProfileBackup(bus.client(), a).publish();
    final stored = bus.stored.last;
    expect(stored.content.contains('Anna'), isFalse, reason: 'encrypted');

    SharedPreferences.setMockInitialValues({});
    final b = await Account.load(prefix: 'me', recover: () async => key);
    expect(b.friends, isEmpty);
    final changed = await ProfileBackup(
      bus.client(),
      b,
    ).restore(timeout: const Duration(milliseconds: 50));
    expect(changed, isTrue);
    expect(b.name, 'Robin');
    expect(b.friends.single.name, 'Anna');
  });
}
