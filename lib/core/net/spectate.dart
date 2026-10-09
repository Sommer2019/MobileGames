import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../account.dart';
import '../mirror.dart';
import 'game_session.dart';
import 'matchmaker.dart';
import 'messenger.dart';
import 'room.dart';

/// Friends watching our online game.
///
/// There is no server, so a spectator connects to the friend who is
/// playing; that device sends the moves so far and then forwards every new
/// one (and the cheers). Only friends may watch.
class SpectatorHub {
  SpectatorHub(this.messenger, this.account, this.sessionFactory) {
    _sub = messenger.messages.where((m) => m.type == 'watch').listen(_onWatch);
    Mirrors.current.addListener(_mirrorChanged);
    _mirrorChanged();
  }

  /// A game on this device (no room) started or stopped.
  void _mirrorChanged() {
    final source = Mirrors.current.value;
    for (final w in List.of(_mirrorWatchers)) {
      if (w.source != source) w.end();
    }
    if (_room == null) playing.value = source?.mirrorGame;
  }

  final List<_MirrorWatcher> _mirrorWatchers = [];

  /// Games whose moves can be replayed for spectators.
  static const watchable = {
    'chess',
    'checkers',
    'mill',
    'connect_four',
    'yahtzee',
    'darts',
    'battleship',
    'billiard',
    'boxes',
    'ludo',
    'domino',
    'halma',
    'bingo',
    'lastcard',
    'stapelfix',
  };
  static const maxWatchers = 10;

  final Messenger messenger;
  final Account account;
  final SessionFactory sessionFactory;
  late final StreamSubscription<DirectMessage> _sub;

  GameRoom? _room;
  final List<_Watcher> _watchers = [];

  /// The game we are playing online and that friends can watch (for the
  /// presence), or null.
  final ValueNotifier<String?> playing = ValueNotifier(null);

  /// Number of friends watching right now.
  final ValueNotifier<int> watchers = ValueNotifier(0);

  /// Our current online game (called by the game screen).
  void attach(GameRoom room) {
    if (room.spectator || !watchable.contains(room.gameId)) return;
    _room = room;
    playing.value = room.gameId;
  }

  void detach(GameRoom room) {
    if (_room != room) return;
    _room = null;
    playing.value = Mirrors.current.value?.mirrorGame;
    for (final w in List.of(_watchers)) {
      w.close();
    }
  }

  void _onWatch(DirectMessage m) {
    final matchId = m.data['matchId'];
    if (matchId is! String) return;
    final room = _room;
    final friend = account.friend(m.from);
    final mirror = Mirrors.current.value;
    final full = _watchers.length + _mirrorWatchers.length >= maxWatchers;
    if (friend == null ||
        full ||
        ((room == null || room.isClosed) && mirror?.mirrorGame == null)) {
      messenger.send(m.from, {'type': 'watch-no', 'matchId': matchId});
      return;
    }
    if (room == null || room.isClosed) {
      final session = sessionFactory(
        MatchInfo(
          matchId: matchId,
          gameId: mirror!.mirrorGame!,
          opponent: m.from,
          opponentName: friend.name,
          isHost: true,
        ),
      );
      final w = _MirrorWatcher(session, mirror, this);
      _mirrorWatchers.add(w);
      watchers.value = _watchers.length + _mirrorWatchers.length;
      w.start();
      return;
    }
    final session = sessionFactory(
      MatchInfo(
        matchId: matchId,
        gameId: room.gameId,
        opponent: m.from,
        opponentName: friend.name,
        isHost: true,
      ),
    );
    final w = _Watcher(session, room, this);
    _watchers.add(w);
    watchers.value = _watchers.length + _mirrorWatchers.length;
    w.start();
  }

  void _remove(_Watcher w) {
    _watchers.remove(w);
    watchers.value = _watchers.length + _mirrorWatchers.length;
  }

  void _removeMirror(_MirrorWatcher w) {
    _mirrorWatchers.remove(w);
    watchers.value = _watchers.length + _mirrorWatchers.length;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    Mirrors.current.removeListener(_mirrorChanged);
    for (final w in List.of(_mirrorWatchers)) {
      w.end();
    }
    for (final w in List.of(_watchers)) {
      w.close();
    }
  }
}

class _Watcher {
  _Watcher(this.session, this.room, this.hub);
  final GameSession session;
  final GameRoom room;
  final SpectatorHub hub;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _sentSnapshot = false;
  bool _closed = false;

  void start() {
    _subs.add(
      session.stateChanges.listen((s) {
        if (s == LinkState.connected && !_sentSnapshot) _snapshot();
        if (s == LinkState.opponentLeft) close();
      }),
    );
    _subs.add(
      session.messages.listen((m) {
        // Spectators can only cheer.
        if (m['k'] == 'x') room.receiveReaction(m);
      }),
    );
    session.start();
  }

  void _snapshot() {
    _sentSnapshot = true;
    session.send({
      'k': 'w',
      'game': room.gameId,
      'names': room.names,
      'seat': room.mySeat,
      'options': room.options,
      'log': room.log,
    });
    _subs.add(room.feed.listen((e) => session.send({'k': 'g', ...e})));
    _subs.add(room.reactionMessages.listen(session.send));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final s in _subs) {
      s.cancel();
    }
    session.close();
    hub._remove(this);
  }
}

/// A friend watching a game that is played on this device only: the
/// state is sent whenever it changed.
class _MirrorWatcher {
  _MirrorWatcher(this.session, this.source, this.hub);
  final GameSession session;
  final MirrorSource source;
  final SpectatorHub hub;
  StreamSubscription<LinkState>? _state;
  Timer? _timer;
  String? _last;
  bool _closed = false;

  void start() {
    _state = session.stateChanges.listen((s) {
      if (s == LinkState.connected && _timer == null) _begin();
      if (s == LinkState.opponentLeft) close();
    });
    session.start();
  }

  void _begin() {
    final state = source.mirrorState();
    _last = jsonEncode(state);
    session.send({
      'k': 'm',
      'game': source.mirrorGame,
      'setup': source.mirrorSetup,
      'state': state,
    });
    _timer = Timer.periodic(source.mirrorInterval, (_) => _tick());
  }

  void _tick() {
    final state = source.mirrorState();
    if (state == null) return;
    final text = jsonEncode(state);
    if (text == _last) return;
    _last = text;
    session.send({'k': 'm', 'state': state});
  }

  /// The game on this device was closed.
  void end() {
    if (_closed) return;
    session.send({'k': 'm', 'end': true});
    // Give the message a moment before the connection goes.
    Timer(const Duration(seconds: 2), close);
    _timer?.cancel();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _state?.cancel();
    session.close();
    hub._removeMirror(this);
  }
}

/// Why watching did not work.
class WatchRefused implements Exception {
  WatchRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Connects to [friend]'s running online game as a spectator.
Future<GameRoom> watchFriend({
  required Messenger messenger,
  required SessionFactory sessionFactory,
  required Friend friend,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final watched = await connectToFriendGame(
    messenger: messenger,
    sessionFactory: sessionFactory,
    friend: friend,
    timeout: timeout,
  );
  if (watched is GameRoom) return watched;
  await (watched as MirrorFeed).close();
  throw WatchRefused('${friend.name} spielt gerade kein Online-Spiel.');
}

/// Connects to whatever [friend] is playing: an online game (a
/// [GameRoom] to watch) or a game on their device (a [MirrorFeed]).
Future<Object> connectToFriendGame({
  required Messenger messenger,
  required SessionFactory sessionFactory,
  required Friend friend,
  Duration timeout = const Duration(seconds: 25),
}) async {
  final matchId = 'w${Random().nextInt(1 << 32).toRadixString(36)}';
  final session = sessionFactory(
    MatchInfo(
      matchId: matchId,
      gameId: 'watch',
      opponent: friend.pubkey,
      opponentName: friend.name,
      isHost: false,
    ),
  );
  final result = Completer<Object>();
  GameRoom? room;
  MirrorFeed? mirror;
  final early = <Map<String, dynamic>>[];
  final refusal = messenger.messages
      .where(
        (m) =>
            m.from == friend.pubkey &&
            m.type == 'watch-no' &&
            m.data['matchId'] == matchId,
      )
      .listen((_) {
        if (!result.isCompleted) {
          result.completeError(
            WatchRefused(
              '${friend.name} spielt gerade kein Spiel zum Zuschauen.',
            ),
          );
        }
      });
  late final StreamSubscription<Map<String, dynamic>> sub;
  final link = session.stateChanges.listen((s) {
    if (s == LinkState.opponentLeft) mirror?.ended.value = true;
  });
  sub = session.messages.listen((m) {
    final r = room;
    if (r != null) {
      r.receive(m);
      return;
    }
    final f = mirror;
    if (f != null) {
      if (m['k'] != 'm') return;
      if (m['end'] == true) f.ended.value = true;
      final state = m['state'];
      if (state is Map) f.state.value = Map<String, dynamic>.from(state);
      return;
    }
    if (m['k'] == 'm' && m['game'] is String) {
      final state = m['state'];
      mirror = MirrorFeed(
        gameId: m['game'] as String,
        friendName: friend.name,
        setup: Map<String, dynamic>.from(m['setup'] as Map? ?? const {}),
        state: state is Map ? Map<String, dynamic>.from(state) : null,
        onClose: () async {
          await sub.cancel();
          await link.cancel();
          await session.close();
        },
      );
      if (!result.isCompleted) result.complete(mirror!);
      return;
    }
    if (m['k'] != 'w') {
      early.add(m);
      return;
    }
    try {
      final created = GameRoom.watching(
        gameId: m['game'] as String,
        seat: m['seat'] as int,
        names: [for (final n in m['names'] as List) n.toString()],
        options: Map<String, dynamic>.from(m['options'] as Map? ?? const {}),
        log: [
          for (final e in m['log'] as List? ?? const [])
            Map<String, dynamic>.from(e as Map),
        ],
        link: session,
      );
      room = created;
      early.forEach(created.receive);
      if (!result.isCompleted) result.complete(created);
    } catch (_) {
      if (!result.isCompleted) {
        result.completeError(WatchRefused('Das Spiel ließ sich nicht laden.'));
      }
    }
  });
  await session.start();
  await messenger.send(friend.pubkey, {'type': 'watch', 'matchId': matchId});
  try {
    return await result.future.timeout(timeout);
  } catch (e) {
    await sub.cancel();
    await link.cancel();
    await session.close();
    if (e is TimeoutException) {
      throw WatchRefused('${friend.name} antwortet nicht.');
    }
    rethrow;
  } finally {
    await refusal.cancel();
  }
}
