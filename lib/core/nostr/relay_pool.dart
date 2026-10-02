import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'event.dart';

/// Minimal publish/subscribe interface on top of Nostr.
/// Implemented by [RelayPool] and by an in-memory bus in tests.
abstract class NostrClient {
  Future<void> publish(NostrEvent event);

  /// Subscribes with a NIP-01 filter. Cancel the stream subscription to close.
  Stream<NostrEvent> subscribe(Map<String, dynamic> filter);
}

/// Public relays used for signaling. No own backend is required: these are
/// free community relays; any of them can fail, so we use several at once.
const defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
  'wss://nostr.mom',
  'wss://relay.nostr.net',
];

class RelayPool implements NostrClient {
  RelayPool({List<String> urls = defaultRelays})
    : _relays = [for (final u in urls) _Relay(u)] {
    for (final r in _relays) {
      r.onEvent = _onEvent;
      r.connect();
    }
  }

  final List<_Relay> _relays;
  final Map<String, _Sub> _subs = {};
  final Random _random = Random();

  /// Number of relays with an open connection.
  int get connectedCount => _relays.where((r) => r.isOpen).length;

  @override
  Future<void> publish(NostrEvent event) async {
    final msg = jsonEncode(['EVENT', event.toJson()]);
    for (final r in _relays) {
      r.send(msg);
    }
  }

  @override
  Stream<NostrEvent> subscribe(Map<String, dynamic> filter) {
    final id = 'mg${_random.nextInt(1 << 31).toRadixString(36)}';
    late final StreamController<NostrEvent> controller;
    controller = StreamController<NostrEvent>(
      onListen: () {
        _subs[id] = _Sub(filter, controller);
        for (final r in _relays) {
          r.addSubscription(id, filter);
        }
      },
      onCancel: () {
        _subs.remove(id);
        for (final r in _relays) {
          r.removeSubscription(id);
        }
      },
    );
    return controller.stream;
  }

  void _onEvent(String subId, Map<String, dynamic> json) {
    final sub = _subs[subId];
    if (sub == null) return;
    final id = json['id'];
    if (id is! String || !sub.seen.add(id)) return;
    if (sub.seen.length > 2000) sub.seen.remove(sub.seen.first);
    try {
      final event = NostrEvent.fromJson(json);
      if (event.isValid) sub.controller.add(event);
    } catch (e) {
      debugPrint('Ignoring malformed event: $e');
    }
  }

  /// Re-establishes lost connections right away.
  void reconnectNow({bool force = false}) {
    for (final r in _relays) {
      r.poke(force: force);
    }
  }

  void dispose() {
    for (final r in _relays) {
      r.dispose();
    }
  }
}

class _Sub {
  _Sub(this.filter, this.controller);
  final Map<String, dynamic> filter;
  final StreamController<NostrEvent> controller;
  // Set literals keep insertion order, so the oldest ids are evicted first.
  final Set<String> seen = <String>{};
}

class _Relay {
  _Relay(this.url);

  final String url;
  WebSocketChannel? _channel;
  bool isOpen = false;
  bool _disposed = false;
  int _attempt = 0;
  final Map<String, Map<String, dynamic>> _subscriptions = {};
  final List<String> _queue = [];
  void Function(String subId, Map<String, dynamic> event)? onEvent;

  Timer? _retry;
  bool _connecting = false;

  /// Reconnects immediately if the connection is down (e.g. after the app
  /// returns from the background).
  void poke({bool force = false}) {
    if (_connecting || _disposed) return;
    if (isOpen && !force) return;
    if (isOpen) {
      // The socket may be silently dead after a long background phase.
      final old = _channel;
      _channel = null;
      isOpen = false;
      old?.sink.close();
    }
    _retry?.cancel();
    _attempt = 0;
    connect();
  }

  Future<void> connect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;
      await ch.ready.timeout(const Duration(seconds: 10));
      isOpen = true;
      _attempt = 0;
      // Only the current channel may trigger a reconnect.
      ch.stream.listen(
        _onMessage,
        onDone: () {
          if (_channel == ch) _onClosed();
        },
        onError: (_) {
          if (_channel == ch) _onClosed();
        },
      );
      for (final e in _subscriptions.entries) {
        _raw(jsonEncode(['REQ', e.key, e.value]));
      }
      final pending = List<String>.from(_queue);
      _queue.clear();
      pending.forEach(_raw);
    } catch (_) {
      _onClosed();
    } finally {
      _connecting = false;
    }
  }

  void _onClosed() {
    isOpen = false;
    _channel = null;
    if (_disposed) return;
    _attempt++;
    final delay = Duration(seconds: min(60, 2 << min(_attempt, 5)));
    _retry?.cancel();
    _retry = Timer(delay, connect);
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String);
      if (msg is List && msg.length >= 3 && msg[0] == 'EVENT') {
        onEvent?.call(
          msg[1] as String,
          Map<String, dynamic>.from(msg[2] as Map),
        );
      }
    } catch (_) {
      // Ignore anything we do not understand (NOTICE, OK, EOSE, ...).
    }
  }

  void _raw(String msg) {
    try {
      _channel?.sink.add(msg);
    } catch (_) {}
  }

  void send(String msg) {
    if (isOpen) {
      _raw(msg);
    } else {
      _queue.add(msg);
      if (_queue.length > 50) _queue.removeAt(0);
    }
  }

  void addSubscription(String id, Map<String, dynamic> filter) {
    _subscriptions[id] = filter;
    if (isOpen) _raw(jsonEncode(['REQ', id, filter]));
  }

  void removeSubscription(String id) {
    if (_subscriptions.remove(id) != null && isOpen) {
      _raw(jsonEncode(['CLOSE', id]));
    }
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
  }
}
