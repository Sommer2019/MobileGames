import 'dart:async';

import 'package:mobile_games/core/nostr/event.dart';
import 'package:mobile_games/core/nostr/relay_pool.dart';

/// In-memory stand-in for the public relays. Like real relays it only
/// forwards ephemeral events to currently open subscriptions.
class FakeRelayBus {
  final List<(Map<String, dynamic>, StreamController<NostrEvent>)> _subs = [];
  final List<NostrEvent> published = [];

  /// Drop every n-th event to simulate unreliable relays (0 = never).
  int dropEvery = 0;

  FakeClient client() => FakeClient(this);

  static bool matches(Map<String, dynamic> f, NostrEvent e) {
    final kinds = f['kinds'] as List?;
    if (kinds != null && !kinds.contains(e.kind)) return false;
    final authors = f['authors'] as List?;
    if (authors != null && !authors.contains(e.pubkey)) return false;
    final since = f['since'] as int?;
    if (since != null && e.createdAt < since) return false;
    for (final key in f.keys.where((k) => k.startsWith('#'))) {
      final tagName = key.substring(1);
      final wanted = f[key] as List;
      if (!e.tags.any(
        (t) => t.length > 1 && t[0] == tagName && wanted.contains(t[1]),
      )) {
        return false;
      }
    }
    return true;
  }

  /// Events relays keep (everything except ephemeral kinds).
  final List<NostrEvent> stored = [];

  void _publish(NostrEvent e) {
    published.add(e);
    if (e.kind < 20000 || e.kind >= 30000) stored.add(e);
    if (dropEvery > 0 && published.length % dropEvery == 0) return;
    for (final (filter, controller) in List.of(_subs)) {
      if (matches(filter, e)) scheduleMicrotask(() => controller.add(e));
    }
  }
}

class FakeClient implements NostrClient {
  FakeClient(this.bus);
  final FakeRelayBus bus;

  @override
  Future<void> publish(NostrEvent event) async {
    expectValid(event);
    bus._publish(event);
  }

  void expectValid(NostrEvent e) {
    if (!e.isValid) throw StateError('invalid event published');
  }

  @override
  Stream<NostrEvent> subscribe(Map<String, dynamic> filter) {
    late (Map<String, dynamic>, StreamController<NostrEvent>) entry;
    final c = StreamController<NostrEvent>(
      onCancel: () => bus._subs.remove(entry),
    );
    entry = (filter, c);
    bus._subs.add(entry);
    // Like a real relay: first the stored events, then live ones.
    for (final e in List.of(bus.stored)) {
      if (FakeRelayBus.matches(filter, e)) scheduleMicrotask(() => c.add(e));
    }
    return c.stream;
  }
}
