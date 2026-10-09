import 'dart:async';
import 'dart:convert';

import 'matchmaker.dart';
import 'messenger.dart';

enum LinkState { connecting, connected, opponentLeft }

/// A direct peer-to-peer pipe (WebRTC data channel in the app, fakes in tests).
abstract class P2pTransport {
  /// Starts the connection. [sendSignal] delivers signaling data to the peer.
  Future<void> start({
    required bool isHost,
    required void Function(Map<String, dynamic>) sendSignal,
  });
  Future<void> onSignal(Map<String, dynamic> signal);
  Stream<String> get incoming;
  Stream<bool> get openChanges;
  bool get isOpen;
  void send(String text);
  Future<void> close();
}

/// Bidirectional game message pipe between two players.
///
/// Tries a direct WebRTC connection; until (or if never) it opens, messages
/// travel end-to-end encrypted through the public Nostr relays. Messages are
/// sequenced so their order survives a switch between both paths.
class GameSession {
  GameSession(
    this.match,
    this.messenger, {
    this.p2p,
    this.helloInterval = const Duration(seconds: 2),
    this.pingInterval = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 90),
  });

  final MatchInfo match;
  final Messenger messenger;

  /// Optional direct connection; without it only the relay path is used.
  final P2pTransport? p2p;
  final Duration helloInterval;
  final Duration pingInterval;
  final Duration timeout;

  // Single subscription: buffers messages until the game screen listens.
  final _messages = StreamController<Map<String, dynamic>>();
  final _state = StreamController<LinkState>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<int, Map<String, dynamic>> _buffer = {};
  Timer? _helloTimer;
  Timer? _pingTimer;
  DateTime _lastSeen = DateTime.now();
  int _sendSeq = 0;
  int _recvSeq = 0;
  bool _closed = false;

  LinkState state = LinkState.connecting;

  /// True while the direct peer-to-peer channel is used.
  bool get isDirect => p2p?.isOpen ?? false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<LinkState> get stateChanges => _state.stream;

  Future<void> start() async {
    _subs.add(
      messenger.messages
          .where(
            (m) =>
                m.from == match.opponent && m.data['matchId'] == match.matchId,
          )
          .listen(_onRelayMessage),
    );
    final p2p = this.p2p;
    if (p2p != null) {
      _subs.add(p2p.incoming.listen(_onP2pText));
      _subs.add(p2p.openChanges.listen((_) => _state.add(state)));
    }
    _sendHello();
    _helloTimer = Timer.periodic(helloInterval, (_) {
      if (state == LinkState.connecting) _sendHello();
    });
    _pingTimer = Timer.periodic(pingInterval, (_) => _ping());
  }

  void _sendHello() => _control({'type': 'hello'});

  void _ping() {
    if (state != LinkState.connected) return;
    if (DateTime.now().difference(_lastSeen) > timeout) {
      _setState(LinkState.opponentLeft);
      return;
    }
    final p2p = this.p2p;
    if (p2p != null && p2p.isOpen) {
      p2p.send(jsonEncode({'c': 'ping'}));
    } else {
      // Relay pings are rarer to stay friendly to the public relays.
      if (DateTime.now().difference(_lastSeen) > timeout ~/ 3) {
        _control({'type': 'ping'});
      }
    }
  }

  void _control(Map<String, dynamic> data) {
    if (_closed) return;
    messenger.send(match.opponent, {...data, 'matchId': match.matchId});
  }

  void _setState(LinkState s) {
    if (state == s || state == LinkState.opponentLeft) return;
    state = s;
    _state.add(s);
  }

  void _seen() {
    _lastSeen = DateTime.now();
    if (state == LinkState.connecting) {
      _setState(LinkState.connected);
      // Make sure the peer also learns that we are here.
      _sendHello();
      // Both sides are listening now, so signaling cannot get lost.
      final p2p = this.p2p;
      if (p2p != null) {
        unawaited(
          p2p
              .start(
                isHost: match.isHost,
                sendSignal: (s) => _control({'type': 'rtc', 'signal': s}),
              )
              .catchError((_) {}),
        );
      }
    }
  }

  void _onRelayMessage(DirectMessage m) {
    switch (m.type) {
      case 'hello':
      case 'pong':
        _seen();
      case 'ping':
        _seen();
        _control({'type': 'pong'});
      case 'rtc':
        _seen();
        final signal = m.data['signal'];
        if (signal is Map<String, dynamic>) {
          p2p?.onSignal(signal).catchError((_) {});
        }
      case 'msg':
        _seen();
        _receive(m.data['seq'], m.data['d']);
      case 'bye':
        _setState(LinkState.opponentLeft);
    }
  }

  void _onP2pText(String text) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      _seen();
      if (data['c'] == 'msg') _receive(data['seq'], data['d']);
      if (data['c'] == 'bye') _setState(LinkState.opponentLeft);
    } catch (_) {}
  }

  void _receive(Object? seq, Object? payload) {
    if (seq is! int || payload is! Map<String, dynamic>) return;
    if (seq < _recvSeq) return; // duplicate
    _buffer[seq] = payload;
    while (_buffer.containsKey(_recvSeq)) {
      _messages.add(_buffer.remove(_recvSeq)!);
      _recvSeq++;
    }
  }

  /// Largest message sent over the direct connection.
  static const maxP2pMessage = 64 * 1024;

  /// Sends a game message to the opponent.
  void send(Map<String, dynamic> payload) {
    if (_closed) return;
    final seq = _sendSeq++;
    final p2p = this.p2p;
    final text = p2p != null && p2p.isOpen
        ? jsonEncode({'c': 'msg', 'seq': seq, 'd': payload})
        : null;
    // Data channels refuse big messages (e.g. the whole game for a new
    // spectator); those go through the relays, which split them. The
    // sequence number keeps the order.
    if (text != null && text.length <= maxP2pMessage) {
      p2p!.send(text);
    } else {
      _control({'type': 'msg', 'seq': seq, 'd': payload});
    }
  }

  /// Leaves the match and tells the opponent.
  Future<void> close() async {
    if (_closed) return;
    final p2p = this.p2p;
    if (p2p != null && p2p.isOpen) p2p.send(jsonEncode({'c': 'bye'}));
    _control({'type': 'bye'});
    _closed = true;
    _helloTimer?.cancel();
    _pingTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await p2p?.close();
  }
}
