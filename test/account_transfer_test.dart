import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/account_transfer.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a transfer code carries the key and nothing else', () {
    final k = KeyPair.generate().privateKey;
    final code = AccountTransfer.codeFor(k);
    expect(code, startsWith('mgkonto1'));
    expect(AccountTransfer.parse(code), k);
    expect(AccountTransfer.parse(AccountTransfer.qrPayload(k)), k);
    expect(AccountTransfer.parse('  $code\n'), k);
    // Friend codes and garbage are no account codes.
    expect(AccountTransfer.parse(pubKeyToNpub(KeyPair(k).publicKey)), isNull);
    expect(AccountTransfer.parse('mgkonto1abc'), isNull);
    expect(AccountTransfer.parse(code.replaceRange(10, 11, 'q')), isNull);
  });

  test('a reinstall follows the redirect to the taken-over account', () async {
    final bus = FakeRelayBus();
    final device = KeyPair.generate().privateKey;
    final taken = KeyPair.generate().privateKey;
    // Without a redirect the device key stays.
    expect(await AccountTransfer.resolve(bus.client(), device), device);

    await AccountTransfer.publishRedirect(bus.client(), device, taken);
    expect(
      await AccountTransfer.resolve(
        bus.client(),
        device,
        timeout: const Duration(milliseconds: 200),
      ),
      taken,
    );
    // Nobody else can read it.
    expect(bus.published.last.content, isNot(contains(taken)));
  });

  test('adopting replaces key, name and friends of this phone', () async {
    final old = await Account.load(recover: () async => null);
    await old.setName('Neues Handy');
    await old.addFriend(KeyPair.generate().publicKey, name: 'Zufall');
    final taken = KeyPair.generate().privateKey;

    await AccountTransfer.adopt(taken);
    final now = await Account.load(recover: () async => null);
    expect(now.keys.privateKey, taken);
    expect(now.friends, isEmpty);
    expect(now.name, startsWith('Spieler '));
  });
}
