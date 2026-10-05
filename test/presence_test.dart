import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a hidden player is not seen online, but still sees others', () async {
    final bus = FakeRelayBus();
    final a = await Account.load(prefix: 'a', recover: () async => null);
    final b = await Account.load(prefix: 'b', recover: () async => null);
    await a.addFriend(b.keys.publicKey);
    await b.addFriend(a.keys.publicKey);

    // B hides before going online.
    SharedPreferences.setMockInitialValues({'presence.hidden': true});
    final pb = Presence(bus.client(), b)..start();
    await settle();
    expect(pb.hidden, isTrue);
    SharedPreferences.setMockInitialValues({});
    final pa = Presence(bus.client(), a)..start();
    await settle();
    expect(pa.isOnline(b.keys.publicKey), isFalse);
    expect(pb.isOnline(a.keys.publicKey), isTrue);

    // Showing it again is announced right away and remembered.
    await pb.setHidden(false);
    await settle();
    expect(pa.isOnline(b.keys.publicKey), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('presence.hidden'), isFalse);
    pa.dispose();
    pb.dispose();
  });
}
