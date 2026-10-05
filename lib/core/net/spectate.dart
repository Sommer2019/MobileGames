import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../account.dart';
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
  }

  /// Games whose moves can be replayed for spectators.
  static const watchable = {
    'chess',
    'checkers',
    'mill',
    'connect_four',
    'yahtzee',
    'darts',
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
    playing.value = null;
    for (final w in List.of(_watchers)) {
      w.close();
    }
  }

  void _onWatch(DirectMessage m) {
    final matchId = m.data['matchId'];
    if (matchId is! String) return;
    final room = _room;
    final friend = account.friend(m.from);
    if (room == null ||
        room.isClosed ||
        friend == null ||
        _watchers.length >= maxWatchers) {
      messenger.send(m.from, {'type': 'watch-no', 'matchId': matchId});
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
    watchers.value = _watchers.length;
    w.start();
  }

  void _remove(_Watcher w) {
    _watchers.remove(w);
    watchers.value = _watchers.length;
  }

  Future<void> dispose() async {
    await _sub.cancel();
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

/// Why watching did not work.
class WatchRefused implements Exception {
  WatchRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Connects to [friend]'s running game as a spectator.
Future<GameRoom> watchFriend({
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
  final result = Completer<GameRoom>();
  GameRoom? room;
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
  final sub = session.messages.listen((m) {
    final r = room;
    if (r != null) {
      r.receive(m);
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
    await session.close();
    if (e is TimeoutException) {
      throw WatchRefused('${friend.name} antwortet nicht.');
    }
    rethrow;
  } finally {
    await refusal.cancel();
  }
}
