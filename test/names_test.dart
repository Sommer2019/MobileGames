import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/names.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('emoji and symbols are removed from names', () {
    expect(cleanName('Anna 🎮'), 'Anna');
    expect(cleanName('🎮Ben🎮'), 'Ben');
    expect(cleanName('Ben ⭐🇩🇪 👨‍👩‍👧'), 'Ben');
    expect(cleanName('Ümit Çelik-Øre'), 'Ümit Çelik-Øre');
    expect(cleanName('  a   b  '), 'a b');
    expect(cleanName('🎮🎮'), '');
    expect(cleanName('x' * 40).length, maxNameLength);
    expect(cleanNameOrNull(42), isNull);
    expect(cleanNameOrNull('🎮'), isNull);
  });

  test('own name and friend names are cleaned', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await Account.load(prefix: 'n');
    await a.setName('Profi 🎮');
    expect(a.name, 'Profi');
    final b = await Account.load(prefix: 'm');
    await a.addFriend(b.keys.publicKey, name: 'Fake 🎮');
    expect(a.friends.single.name, 'Fake');
    await a.updateFriendName(b.keys.publicKey, 'Neu 🎮');
    expect(a.friends.single.name, 'Neu');
  });

  test('the name field drops emoji while typing', () {
    final f = NameInputFormatter();
    final out = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'Max🎮'),
    );
    expect(out.text, 'Max');
  });
}
