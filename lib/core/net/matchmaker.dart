import 'dart:async';
import 'dart:convert';

import '../names.dart';
import '../nostr/event.dart';
import '../nostr/keys.dart';
import 'messenger.dart';

/// Result of matchmaking: who plays against whom, and who hosts.
/// The host starts the game (white in chess, first player otherwise)
/// and creates the WebRTC offer.
class MatchInfo {
  const MatchInfo({
    required this.matchId,
    required this.gameId,
    required this.opponent,
    required this.opponentName,
    required this.isHost,
  });

  final String matchId;
  final String gameId;
  final String opponent;
  final String opponentName;
  final bool isHost;
}

class IncomingInvite {
  IncomingInvite(this.from, this.fromName, this.gameId, this.matchId);
  final String from;
  final String fromName;
  final String gameId;
  final String matchId;
}

class MatchmakingCancelled implements Exception {
  @override
  String toString() => 'Matchmaking abgebrochen';
}

/// Finds opponents through Nostr relays, either random players that are
/// searching for the same game, or friends via direct invites.
class Matchmaker {
  Matchmaker(
    this.messenger, {
    required this.nameProvider,
    this.seekInterval = const Duration(seconds: 4),
    this.handshakeTimeout = const Duration(seconds: 8),
    this.inviteTimeout = const Duration(seconds: 90),
  }) {
    _msgSub = messenger.messages.listen(_onMessage);
  }

  final Messenger messenger;
  final String Function() nameProvider;
  final Duration seekInterval;
  final Duration handshakeTimeout;
  final Duration inviteTimeout;

  late final StreamSubscription<DirectMessage> _msgSub;
  final _invites = StreamController<IncomingInvite>.broadcast();
  final _cancelledInvites = StreamController<String>.broadcast();
  final Map<String, IncomingInvite> _openInvites = {};

  _Seek? _seek;
  final Map<String, _PendingInvite> _sentInvites = {};
  final Map<String, Completer<MatchInfo?>> _awaitingConfirm = {};

  String get me => messenger.me;
  Stream<IncomingInvite> get invites => _invites.stream;

  /// Emits match ids of invites the sender withdrew.
  Stream<String> get cancelledInvites => _cancelledInvites.stream;

  static String seekTag(String gameId) => 'mobilegames-seek-$gameId';

  // ---------------------------------------------------------------- random

  /// Searches a random opponent for [gameId]. Completes with the match or
  /// throws [MatchmakingCancelled] when [cancelRandom] is called.
  Future<MatchInfo> findRandom(String gameId) {
    cancelRandom();
    final seek = _Seek(gameId);
    _seek = seek;
    void publishSeek() {
      messenger.client.publish(
        NostrEvent.create(
          keys: messenger.keys,
          kind: Kinds.seek,
          content: jsonEncode({'name': nameProvider(), 'v': 1}),
          tags: [
            ['t', seekTag(gameId)],
          ],
        ),
      );
    }

    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
    seek.sub = messenger.client
        .subscribe({
          'kinds': [Kinds.seek],
          '#t': [seekTag(gameId)],
          'since': since,
        })
        .listen((e) => _onSeek(seek, e));
    publishSeek();
    seek.timer = Timer.periodic(seekInterval, (_) => publishSeek());
    return seek.completer.future;
  }

  void cancelRandom() {
    final s = _seek;
    if (s == null) return;
    _seek = null;
    s.dispose();
    if (!s.completer.isCompleted) {
      s.completer.completeError(MatchmakingCancelled());
    }
  }

  void _onSeek(_Seek seek, NostrEvent e) {
    if (_seek != seek || e.pubkey == me) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - e.createdAt > 20) return;
    // Deterministic tie-break: the smaller public key proposes the match,
    // so two seekers never both propose to each other.
    if (me.compareTo(e.pubkey) >= 0) return;
    if (seek.proposedTo != null || seek.awaitingConfirmFrom != null) return;
    String name = 'Spieler';
    try {
      name = cleanNameOrNull((jsonDecode(e.content) as Map)['name']) ?? name;
    } catch (_) {}
    final matchId = randomHex(8);
    seek
      ..proposedTo = e.pubkey
      ..proposedName = name
      ..proposedMatch = matchId;
    seek.proposalTimer = Timer(handshakeTimeout, () {
      seek.proposedTo = null;
      seek.proposedMatch = null;
    });
    messenger.send(e.pubkey, {
      'type': 'match-offer',
      'matchId': matchId,
      'game': seek.gameId,
      'name': nameProvider(),
    });
  }

  // --------------------------------------------------------------- friends

  /// Match id of the most recent invite sent (to cancel it).
  String? lastInviteId;

  /// Invites a friend. Completes with the match, or null if declined/timeout.
  Future<MatchInfo?> inviteFriend(
    String friend,
    String friendName,
    String gameId,
  ) {
    final matchId = randomHex(8);
    lastInviteId = matchId;
    final pending = _PendingInvite(friend, friendName, gameId, matchId);
    _sentInvites[matchId] = pending;
    pending.timer = Timer(inviteTimeout, () => _finishInvite(matchId, null));
    messenger.send(friend, {
      'type': 'invite',
      'matchId': matchId,
      'game': gameId,
      'name': nameProvider(),
    });
    return pending.completer.future;
  }

  void cancelInvite(String matchId) {
    final p = _sentInvites[matchId];
    if (p == null) return;
    messenger.send(p.friend, {'type': 'invite-cancel', 'matchId': matchId});
    _finishInvite(matchId, null);
  }

  void _finishInvite(String matchId, MatchInfo? result) {
    final p = _sentInvites.remove(matchId);
    if (p == null) return;
    p.timer?.cancel();
    if (!p.completer.isCompleted) p.completer.complete(result);
  }

  /// Accepts an invite. Completes with the match, or null if the inviter
  /// is gone.
  Future<MatchInfo?> acceptInvite(IncomingInvite invite) {
    _openInvites.remove(invite.matchId);
    _acceptedInvites[invite.matchId] = invite;
    final c = Completer<MatchInfo?>();
    _awaitingConfirm[invite.matchId] = c;
    messenger.send(invite.from, {
      'type': 'invite-accept',
      'matchId': invite.matchId,
      'name': nameProvider(),
    });
    Timer(handshakeTimeout, () {
      _acceptedInvites.remove(invite.matchId);
      if (_awaitingConfirm.remove(invite.matchId) != null && !c.isCompleted) {
        c.complete(null);
      }
    });
    return c.future;
  }

  void declineInvite(IncomingInvite invite) {
    _openInvites.remove(invite.matchId);
    messenger.send(invite.from, {
      'type': 'invite-decline',
      'matchId': invite.matchId,
    });
  }

  // -------------------------------------------------------------- messages

  void _onMessage(DirectMessage m) {
    final matchId = m.data['matchId'];
    if (matchId is! String) return;
    switch (m.type) {
      case 'match-offer':
        final seek = _seek;
        if (seek == null ||
            seek.gameId != m.data['game'] ||
            seek.proposedTo != null ||
            seek.awaitingConfirmFrom != null) {
          return;
        }
        seek.awaitingConfirmFrom = m.from;
        seek.awaitingMatch = matchId;
        seek.awaitingName = cleanNameOrNull(m.data['name']) ?? 'Spieler';
        seek.confirmTimer = Timer(handshakeTimeout, () {
          seek.awaitingConfirmFrom = null;
          seek.awaitingMatch = null;
        });
        messenger.send(m.from, {
          'type': 'match-accept',
          'matchId': matchId,
          'name': nameProvider(),
        });
      case 'match-accept':
        final seek = _seek;
        if (seek != null &&
            seek.proposedTo == m.from &&
            seek.proposedMatch == matchId) {
          messenger.send(m.from, {'type': 'match-confirm', 'matchId': matchId});
          _completeSeek(
            MatchInfo(
              matchId: matchId,
              gameId: seek.gameId,
              opponent: m.from,
              opponentName:
                  cleanNameOrNull(m.data['name']) ??
                  seek.proposedName ??
                  'Spieler',
              isHost: true,
            ),
          );
        } else {
          // Too late, we already matched with someone else.
          messenger.send(m.from, {'type': 'match-reject', 'matchId': matchId});
        }
      case 'match-confirm':
        final seek = _seek;
        if (seek != null &&
            seek.awaitingConfirmFrom == m.from &&
            seek.awaitingMatch == matchId) {
          _completeSeek(
            MatchInfo(
              matchId: matchId,
              gameId: seek.gameId,
              opponent: m.from,
              opponentName: seek.awaitingName ?? 'Spieler',
              isHost: false,
            ),
          );
        }
      case 'match-reject':
        final seek = _seek;
        if (seek != null && seek.awaitingMatch == matchId) {
          seek.confirmTimer?.cancel();
          seek.awaitingConfirmFrom = null;
          seek.awaitingMatch = null;
        }
      case 'invite':
        final game = m.data['game'];
        if (game is! String) return;
        final invite = IncomingInvite(
          m.from,
          cleanNameOrNull(m.data['name']) ?? 'Spieler',
          game,
          matchId,
        );
        _openInvites[matchId] = invite;
        _invites.add(invite);
      case 'invite-cancel':
        if (_openInvites.remove(matchId) != null) {
          _cancelledInvites.add(matchId);
        }
        final c = _awaitingConfirm.remove(matchId);
        if (c != null && !c.isCompleted) c.complete(null);
      case 'invite-accept':
        final p = _sentInvites[matchId];
        if (p == null || p.friend != m.from) {
          messenger.send(m.from, {'type': 'invite-cancel', 'matchId': matchId});
          return;
        }
        messenger.send(m.from, {'type': 'invite-confirm', 'matchId': matchId});
        _finishInvite(
          matchId,
          MatchInfo(
            matchId: matchId,
            gameId: p.gameId,
            opponent: p.friend,
            opponentName: cleanNameOrNull(m.data['name']) ?? p.friendName,
            isHost: true,
          ),
        );
      case 'invite-decline':
        final p = _sentInvites[matchId];
        if (p != null && p.friend == m.from) _finishInvite(matchId, null);
      case 'invite-confirm':
        final c = _awaitingConfirm.remove(matchId);
        if (c == null || c.isCompleted) return;
        final invite = _lastInviteFrom(m.from, matchId);
        c.complete(
          MatchInfo(
            matchId: matchId,
            gameId: invite?.gameId ?? '',
            opponent: m.from,
            opponentName: invite?.fromName ?? 'Freund',
            isHost: false,
          ),
        );
    }
  }

  final Map<String, IncomingInvite> _acceptedInvites = {};

  IncomingInvite? _lastInviteFrom(String from, String matchId) {
    final i = _acceptedInvites.remove(matchId);
    return (i != null && i.from == from) ? i : null;
  }

  void _completeSeek(MatchInfo info) {
    final s = _seek;
    if (s == null) return;
    _seek = null;
    s.dispose();
    if (!s.completer.isCompleted) s.completer.complete(info);
  }

  Future<void> dispose() async {
    cancelRandom();
    await _msgSub.cancel();
  }
}

class _Seek {
  _Seek(this.gameId);
  final String gameId;
  final completer = Completer<MatchInfo>();
  StreamSubscription<NostrEvent>? sub;
  Timer? timer;
  Timer? proposalTimer;
  Timer? confirmTimer;
  String? proposedTo;
  String? proposedName;
  String? proposedMatch;
  String? awaitingConfirmFrom;
  String? awaitingMatch;
  String? awaitingName;

  void dispose() {
    sub?.cancel();
    timer?.cancel();
    proposalTimer?.cancel();
    confirmTimer?.cancel();
  }
}

class _PendingInvite {
  _PendingInvite(this.friend, this.friendName, this.gameId, this.matchId);
  final String friend;
  final String friendName;
  final String gameId;
  final String matchId;
  final completer = Completer<MatchInfo?>();
  Timer? timer;
}
