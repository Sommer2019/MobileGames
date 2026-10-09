import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/net/messenger.dart';
import 'package:mobile_games/core/nostr/event.dart';
import 'package:mobile_games/core/nostr/keys.dart';
import 'package:mobile_games/core/nostr/relay_pool.dart';

import 'fake_nostr.dart';

/// Holds back published events until [release], which sends them in
/// reverse order (relays do not guarantee any order).
class _ReversingClient implements NostrClient {
  _ReversingClient(this.inner);
  final FakeClient inner;
  final held = <NostrEvent>[];

  @override
  Future<void> publish(NostrEvent event) async => held.add(event);

  Future<void> release() async {
    for (final e in held.reversed) {
      await inner.publish(e);
    }
    held.clear();
  }

  @override
  Stream<NostrEvent> subscribe(Map<String, dynamic> filter) =>
      inner.subscribe(filter);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('big messages are split and put back together', () async {
    final bus = FakeRelayBus();
    final a = Messenger(bus.client(), KeyPair.generate())..start();
    final b = Messenger(bus.client(), KeyPair.generate())..start();
    final got = <DirectMessage>[];
    b.messages.listen(got.add);

    // ~200 KB with multi-byte characters (split inside a character).
    final big = List.generate(40000, (i) => 'ä€$i').join();
    await a.send(b.me, {'type': 'state', 'big': big});
    await a.send(b.me, {'type': 'small'});
    await _settle();

    expect(bus.published.length, greaterThan(5));
    for (final e in bus.published) {
      expect(e.content.length, lessThan(64 * 1024));
    }
    expect(got.map((m) => m.type), ['state', 'small']);
    expect(got.first.data['big'], big);
    expect(got.first.from, a.me);
  });

  test('pieces arriving in any order are reassembled', () async {
    final bus = FakeRelayBus();
    final sender = _ReversingClient(bus.client());
    final a = Messenger(sender, KeyPair.generate());
    final b = Messenger(bus.client(), KeyPair.generate())..start();
    final got = <DirectMessage>[];
    b.messages.listen(got.add);

    final big = 'x' * (Messenger.maxPlain * 3 + 17);
    await a.send(b.me, {'type': 'state', 'big': big});
    expect(sender.held.length, 4);
    await sender.release();
    await _settle();

    expect(got, hasLength(1));
    expect(got.single.data['big'], big);
  });

  test('a missing piece never delivers a broken message', () async {
    final bus = FakeRelayBus()..dropEvery = 2;
    final a = Messenger(bus.client(), KeyPair.generate())..start();
    final b = Messenger(bus.client(), KeyPair.generate())..start();
    final got = <DirectMessage>[];
    b.messages.listen(got.add);

    await a.send(b.me, {'type': 'state', 'big': 'y' * 100000});
    await _settle();
    expect(got, isEmpty);
  });
}
