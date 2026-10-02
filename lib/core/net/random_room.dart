import 'dart:async';
import 'dart:convert';

import '../nostr/event.dart';
import '../nostr/keys.dart';
import 'matchmaker.dart';
import 'messenger.dart';

sealed class RoomSearchEvent {}

/// This device now hosts a public room and waits for players.
class HostingStarted extends RoomSearchEvent {}

/// A random player joined our room (we are host).
class GuestJoined extends RoomSearchEvent {
  GuestJoined(this.match);
  final MatchInfo match;
}

/// We joined somebody else's room (we are guest). Final event.
class JoinedRoom extends RoomSearchEvent {
  JoinedRoom(this.match);
  final MatchInfo match;
}

enum _Phase { looking, joining, hosting, done }

/// Finds random players for games with more than two players.
///
/// Every searcher first looks for an advertised open room for the same game
/// and size and asks to join it. If there is none, it advertises its own
/// room. If two rooms appear at the same time, the empty room of the host
/// with the larger public key dissolves and joins the other one.
class RandomRoomSearch {
  RandomRoomSearch(
    this.messenger, {
    required this.gameId,
    required this.size,
    required this.nameProvider,
    this.lookTime = const Duration(seconds: 3),
    this.advertInterval = const Duration(seconds: 4),
    this.handshakeTimeout = const Duration(seconds: 8),
  });

  final Messenger messenger;
  final String gameId;
  final int size;
  final String Function() nameProvider;
  final Duration lookTime;
  final Duration advertInterval;
  final Duration handshakeTimeout;

  final _events = StreamController<RoomSearchEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  final Map<String, (String roomId, int count, DateTime seen)> _adverts = {};
  final Map<String, DateTime> _rejected = {};
  _Phase _phase = _Phase.looking;
  Timer? _timer;
  Timer? _advertTimer;
  String? _joiningHost;
  String? _joiningRoom;
  String _roomId = '';
  int _guests = 0;
  bool _full = false;

  Stream<RoomSearchEvent> get events => _events.stream;
  String get me => messenger.me;
  String get tag => 'mobilegames-room-$gameId-$size';
  bool get isHosting => _phase == _Phase.hosting;

  void start() {
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
    _subs.add(
      messenger.client
          .subscribe({
            'kinds': [Kinds.seek],
            '#t': [tag],
            'since': since,
          })
          .listen(_onAdvert),
    );
    _subs.add(messenger.messages.listen(_onMessage));
    _look();
  }

  void _look() {
    _phase = _Phase.looking;
    _timer?.cancel();
    if (!_tryJoin()) _timer = Timer(lookTime, _host);
  }

  bool _tryJoin() {
    final now = DateTime.now();
    final candidates =
        _adverts.entries
            .where(
              (e) =>
                  e.value.$2 < size &&
                  now.difference(e.value.$3) < advertInterval * 3 &&
                  !_rejected.containsKey(e.key),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (candidates.isEmpty) return false;
    final host = candidates.first;
    _phase = _Phase.joining;
    _joiningHost = host.key;
    _joiningRoom = host.value.$1;
    messenger.send(host.key, {
      'type': 'room-join',
      'room': host.value.$1,
      'name': nameProvider(),
    });
    _timer?.cancel();
    _timer = Timer(handshakeTimeout, () {
      if (_phase != _Phase.joining) return;
      _rejected[host.key] = DateTime.now();
      _look();
    });
    return true;
  }

  void _host() {
    if (_phase != _Phase.looking) return;
    _phase = _Phase.hosting;
    _roomId = randomHex(8);
    _events.add(HostingStarted());
    _advertise();
    _advertTimer = Timer.periodic(advertInterval, (_) => _advertise());
  }

  void _advertise() {
    if (_phase != _Phase.hosting || _full) return;
    messenger.client.publish(
      NostrEvent.create(
        keys: messenger.keys,
        kind: Kinds.seek,
        content: jsonEncode({
          'room': _roomId,
          'count': _guests + 1,
          'name': nameProvider(),
        }),
        tags: [
          ['t', tag],
        ],
      ),
    );
  }

  void _onAdvert(NostrEvent e) {
    if (e.pubkey == me) return;
    try {
      final c = jsonDecode(e.content) as Map;
      _adverts[e.pubkey] = (
        c['room'] as String,
        c['count'] as int? ?? 1,
        DateTime.now(),
      );
    } catch (_) {
      return;
    }
    switch (_phase) {
      case _Phase.looking:
        _tryJoin();
      case _Phase.hosting:
        // Two empty rooms: the one with the larger key gives up.
        if (_guests == 0 && e.pubkey.compareTo(me) < 0) {
          _advertTimer?.cancel();
          _phase = _Phase.looking;
          _tryJoin();
          if (_phase == _Phase.looking) _host();
        }
      case _Phase.joining:
      case _Phase.done:
        break;
    }
  }

  void _onMessage(DirectMessage m) {
    switch (m.type) {
      case 'room-join':
        if (_phase != _Phase.hosting || m.data['room'] != _roomId) {
          messenger.send(m.from, {'type': 'room-full', 'room': m.data['room']});
          return;
        }
        if (_full || _guests + 1 >= size) {
          messenger.send(m.from, {'type': 'room-full', 'room': _roomId});
          return;
        }
        _guests++;
        final matchId = randomHex(8);
        messenger.send(m.from, {
          'type': 'room-accept',
          'room': _roomId,
          'matchId': matchId,
          'name': nameProvider(),
        });
        _events.add(
          GuestJoined(
            MatchInfo(
              matchId: matchId,
              gameId: gameId,
              opponent: m.from,
              opponentName: m.data['name'] as String? ?? 'Spieler',
              isHost: true,
            ),
          ),
        );
        if (_guests + 1 >= size) markFull();
      case 'room-accept':
        if (_phase != _Phase.joining ||
            m.from != _joiningHost ||
            m.data['room'] != _joiningRoom) {
          return;
        }
        final matchId = m.data['matchId'];
        if (matchId is! String) return;
        _phase = _Phase.done;
        _timer?.cancel();
        _events.add(
          JoinedRoom(
            MatchInfo(
              matchId: matchId,
              gameId: gameId,
              opponent: m.from,
              opponentName: m.data['name'] as String? ?? 'Host',
              isHost: false,
            ),
          ),
        );
        _stopListening();
      case 'room-full':
        if (_phase == _Phase.joining && m.from == _joiningHost) {
          _rejected[m.from] = DateTime.now();
          _look();
        }
    }
  }

  /// Host: stop advertising (room full or game started).
  void markFull() {
    _full = true;
    _advertTimer?.cancel();
  }

  void _stopListening() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _advertTimer?.cancel();
  }

  void cancel() {
    _phase = _Phase.done;
    _timer?.cancel();
    _stopListening();
  }
}
