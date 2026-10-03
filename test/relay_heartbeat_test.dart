import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/nostr/relay_pool.dart';

/// A local WebSocket relay. When [answer] is false it swallows everything,
/// like a connection that died without being closed.
class _Relay {
  _Relay(this.server) {
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      connections++;
      ws.listen((data) {
        final msg = jsonDecode(data as String) as List;
        if (answer && msg[0] == 'REQ') ws.add(jsonEncode(['EOSE', msg[1]]));
      });
    });
  }

  static Future<_Relay> start() async =>
      _Relay(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  int connections = 0;
  bool answer = true;
  String get url => 'ws://127.0.0.1:${server.port}';
}

Future<void> waitFor(bool Function() ok) async {
  for (var i = 0; i < 100 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('a relay that stops answering is reconnected', () async {
    final relay = await _Relay.start();
    final pool = RelayPool(
      urls: [relay.url],
      heartbeat: const Duration(milliseconds: 200),
    );
    addTearDown(() async {
      pool.dispose();
      await relay.server.close(force: true);
    });
    await waitFor(() => pool.connectedCount == 1);
    expect(relay.connections, 1);

    // Answers keep the connection.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(relay.connections, 1);

    // Silence: the connection is replaced.
    relay.answer = false;
    await waitFor(() => relay.connections > 1);
    expect(relay.connections, greaterThan(1));
    expect(pool.status.single.url, relay.url);
  });

  test('a relay that cannot be reached reports why', () async {
    final pool = RelayPool(urls: ['ws://127.0.0.1:1']);
    addTearDown(pool.dispose);
    await waitFor(() => pool.status.single.error != null);
    expect(pool.status.single.open, isFalse);
    expect(pool.status.single.error, isNotNull);
  });
}
