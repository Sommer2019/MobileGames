import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_session.dart';
import 'matchmaker.dart';

/// A message inside a game room, tagged with the sender's seat.
class RoomMessage {
  const RoomMessage(this.seat, this.data);
  final int seat;
  final Map<String, dynamic> data;
}

class ChatLine {
  ChatLine(this.seat, this.name, this.text, {DateTime? time})
    : time = time ?? DateTime.now();
  final int seat;
  final String name;
  final String text;
  final DateTime time;
}

typedef SessionFactory = GameSession Function(MatchInfo match);

/// A running online game with 2–4 players.
///
/// The topology is a star: the host (seat 0) has one peer-to-peer
/// [GameSession] to every guest and forwards messages between them, so the
/// host also defines one consistent message order for everybody.
class GameRoom extends ChangeNotifier {
  GameRoom._({
    required this.gameId,
    required this.mySeat,
    required this.names,
    required List<GameSession> links,
    this.options = const {},
  }) : _links = links;

  final String gameId;
  final int mySeat;

  /// Player names by seat.
  final List<String> names;

  /// Game options chosen by the host (e.g. board size).
  final Map<String, dynamic> options;
  final List<GameSession> _links;

  final List<_Listener> _listeners = [];
  final List<RoomMessage> _unclaimed = [];
  final List<ChatLine> chat = [];
  final _chat = StreamController<ChatLine>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Name of the player that left; the game cannot continue then.
  String? leftPlayer;
  bool _closed = false;

  bool get isHost => mySeat == 0;
  int get size => names.length;
  bool get isDirect => _links.isNotEmpty && _links.every((l) => l.isDirect);

  /// Game messages from the other players (buffered until listened to).
  Stream<RoomMessage> get messages => messagesWhere((_) => true);

  /// Game messages matching [test]. Messages that no current listener wants
  /// are kept and handed to the next matching listener, so nothing gets
  /// lost while one game screen closes and the next one opens.
  Stream<RoomMessage> messagesWhere(bool Function(RoomMessage m) test) {
    late final _Listener listener;
    final controller = StreamController<RoomMessage>(
      onCancel: () => _listeners.remove(listener),
    );
    listener = _Listener(test, controller);
    controller.onListen = () {
      _listeners.add(listener);
      final mine = _unclaimed.where(test).toList();
      _unclaimed.removeWhere(mine.contains);
      mine.forEach(controller.add);
    };
    return controller.stream;
  }

  void _dispatch(RoomMessage m) {
    var claimed = false;
    for (final l in List.of(_listeners)) {
      if (l.test(m)) {
        l.controller.add(m);
        claimed = true;
      }
    }
    if (!claimed) {
      _unclaimed.add(m);
      if (_unclaimed.length > 500) _unclaimed.removeAt(0);
    }
  }

  Stream<ChatLine> get chatStream => _chat.stream;

  String nameOf(int seat) => seat == mySeat ? 'Du' : names[seat];

  void _attach() {
    for (var i = 0; i < _links.length; i++) {
      final link = _links[i];
      _subs.add(
        link.stateChanges.listen((s) {
          if (s == LinkState.opponentLeft) {
            _playerLeft(isHost ? i + 1 : 0);
          } else {
            notifyListeners();
          }
        }),
      );
    }
  }

  void _onLinkMessage(int linkIndex, Map<String, dynamic> m) {
    if (_closed) return;
    // The host knows who sent a message, guests trust the host.
    final seat = isHost ? linkIndex + 1 : (m['s'] as int? ?? 0);
    switch (m['k']) {
      case 'g':
        final d = m['d'];
        if (d is! Map<String, dynamic>) return;
        _dispatch(RoomMessage(seat, d));
        if (isHost) _forward(linkIndex, {'k': 'g', 's': seat, 'd': d});
      case 'c':
        final text = m['text'];
        if (text is! String || seat >= size) return;
        _addChat(ChatLine(seat, names[seat], text));
        if (isHost) _forward(linkIndex, {'k': 'c', 's': seat, 'text': text});
      case 'l':
        _playerLeft(m['s'] as int? ?? 0);
    }
  }

  void _forward(int exceptLink, Map<String, dynamic> m) {
    for (var i = 0; i < _links.length; i++) {
      if (i != exceptLink) _links[i].send(m);
    }
  }

  void _addChat(ChatLine line) {
    chat.add(line);
    if (chat.length > 200) chat.removeAt(0);
    _chat.add(line);
    notifyListeners();
  }

  void _playerLeft(int seat) {
    if (leftPlayer != null || _closed) return;
    leftPlayer = seat < size ? names[seat] : 'Ein Spieler';
    if (isHost) _forward(seat - 1, {'k': 'l', 's': seat});
    notifyListeners();
  }

  /// Sends a game message to all other players.
  void send(Map<String, dynamic> data) {
    if (_closed) return;
    for (final l in _links) {
      l.send({'k': 'g', 's': mySeat, 'd': data});
    }
  }

  void sendChat(String text) {
    final t = text.trim();
    if (t.isEmpty || _closed) return;
    final msg = t.length > 500 ? t.substring(0, 500) : t;
    for (final l in _links) {
      l.send({'k': 'c', 's': mySeat, 'text': msg});
    }
    _addChat(ChatLine(mySeat, names[mySeat], msg));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    for (final l in _links) {
      await l.close();
    }
  }
}

class _Listener {
  _Listener(this.test, this.controller);
  final bool Function(RoomMessage) test;
  final StreamController<RoomMessage> controller;
}

enum GuestStatus { connecting, connected, left }

class RoomGuestEntry {
  RoomGuestEntry(this.match, this.session);
  final MatchInfo match;
  final GameSession session;
  final List<Map<String, dynamic>> early = [];
  GuestStatus status = GuestStatus.connecting;
  StreamSubscription<Map<String, dynamic>>? sub;
  StreamSubscription<LinkState>? stateSub;
}

/// Host side before the game starts: collects guests, then starts the game.
class RoomHost extends ChangeNotifier {
  RoomHost({
    required this.gameId,
    required this.maxPlayers,
    required this.myName,
    required this.sessionFactory,
  });

  final String gameId;
  final int maxPlayers;
  final String myName;
  final SessionFactory sessionFactory;
  final List<RoomGuestEntry> guests = [];
  GameRoom? room;
  bool _closed = false;

  List<RoomGuestEntry> get connected =>
      guests.where((g) => g.status == GuestStatus.connected).toList();
  bool get isFull =>
      guests.where((g) => g.status != GuestStatus.left).length + 1 >=
      maxPlayers;
  bool get canStart => connected.isNotEmpty;

  void addGuest(MatchInfo match) {
    if (_closed || room != null) return;
    final session = sessionFactory(match);
    final entry = RoomGuestEntry(match, session);
    guests.add(entry);
    entry.sub = session.messages.listen((m) {
      final r = room;
      if (r == null) {
        entry.early.add(m);
      } else {
        r._onLinkMessage(r._links.indexOf(session), m);
      }
    });
    entry.stateSub = session.stateChanges.listen((s) {
      if (room != null) return;
      entry.status = switch (s) {
        LinkState.connecting => GuestStatus.connecting,
        LinkState.connected => GuestStatus.connected,
        LinkState.opponentLeft => GuestStatus.left,
      };
      notifyListeners();
    });
    session.start();
    notifyListeners();
  }

  /// Starts the game with all connected guests.
  GameRoom start({Map<String, dynamic> options = const {}}) {
    final players = connected;
    for (final g in guests.where((g) => !players.contains(g))) {
      g.sub?.cancel();
      g.stateSub?.cancel();
      g.session.close();
    }
    final names = [myName, for (final g in players) g.match.opponentName];
    final r = GameRoom._(
      gameId: gameId,
      mySeat: 0,
      names: names,
      links: [for (final g in players) g.session],
      options: options,
    );
    room = r;
    for (var i = 0; i < players.length; i++) {
      final g = players[i];
      g.stateSub?.cancel();
      g.session.send({
        'k': 'r',
        'names': names,
        'seat': i + 1,
        'game': gameId,
        'options': options,
      });
      for (final m in g.early) {
        r._onLinkMessage(i, m);
      }
    }
    r._attach();
    return r;
  }

  /// Cancels the lobby (only if the game was not started).
  Future<void> close() async {
    if (_closed || room != null) return;
    _closed = true;
    for (final g in guests) {
      await g.sub?.cancel();
      await g.stateSub?.cancel();
      await g.session.close();
    }
  }
}

/// Guest side before the game starts: connects to the host and waits for
/// the roster.
class RoomGuest {
  RoomGuest(this.match, SessionFactory factory) : session = factory(match) {
    _sub = session.messages.listen(_onMessage);
    _stateSub = session.stateChanges.listen((s) {
      if (s == LinkState.opponentLeft && !_room.isCompleted) {
        _room.completeError(StateError('Host hat den Raum verlassen'));
      }
      status.value = s;
    });
    session.start();
    // Errors are handled by whoever awaits [room]; avoid unhandled errors.
    _room.future.then((_) {}, onError: (_) {});
  }

  final MatchInfo match;
  final GameSession session;
  final status = ValueNotifier<LinkState>(LinkState.connecting);
  final _room = Completer<GameRoom>();
  late final StreamSubscription<Map<String, dynamic>> _sub;
  late final StreamSubscription<LinkState> _stateSub;
  GameRoom? _started;
  final List<Map<String, dynamic>> _early = [];

  /// Completes when the host starts the game.
  Future<GameRoom> get room => _room.future;

  void _onMessage(Map<String, dynamic> m) {
    final r = _started;
    if (r != null) {
      r._onLinkMessage(0, m);
      return;
    }
    if (m['k'] != 'r') {
      _early.add(m);
      return;
    }
    final names = [for (final n in m['names'] as List) n.toString()];
    final r2 = GameRoom._(
      gameId: m['game'] as String? ?? match.gameId,
      mySeat: m['seat'] as int,
      names: names,
      links: [session],
      options: Map<String, dynamic>.from(m['options'] as Map? ?? const {}),
    );
    _started = r2;
    _stateSub.cancel();
    r2._attach();
    for (final e in _early) {
      r2._onLinkMessage(0, e);
    }
    if (!_room.isCompleted) _room.complete(r2);
  }

  Future<void> close() async {
    if (_started != null) return;
    await _sub.cancel();
    await _stateSub.cancel();
    await session.close();
    if (!_room.isCompleted) _room.completeError(StateError('abgebrochen'));
  }
}
