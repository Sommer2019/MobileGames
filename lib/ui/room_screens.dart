import 'dart:async';

import 'package:flutter/material.dart';

import '../core/net/matchmaker.dart';
import '../core/net/random_room.dart';
import '../core/net/room.dart';
import '../core/services.dart';
import '../games/registry.dart';
import 'play_setup.dart';

/// Replaces the current route with the game screen for [room].
void openGameRoom(BuildContext context, GameRoom room) {
  final game = gameById(room.gameId);
  if (game == null || game.multiplayerBuilder == null) {
    room.close();
    return;
  }
  Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => game.multiplayerBuilder!(PlaySetup.online(room)),
    ),
  );
}

RoomHost _newHost(GameInfo game, int maxPlayers) => RoomHost(
  gameId: game.id,
  maxPlayers: maxPlayers,
  myName: Services.I.account.name,
  sessionFactory: Services.I.createSession,
);

class _PlayerList extends StatelessWidget {
  const _PlayerList({required this.host});
  final RoomHost host;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.star)),
          title: Text('${host.myName} (du, Host)'),
        ),
        for (final g in host.guests)
          ListTile(
            leading: CircleAvatar(
              child: Text(
                g.match.opponentName.isEmpty
                    ? '?'
                    : g.match.opponentName[0].toUpperCase(),
              ),
            ),
            title: Text(g.match.opponentName),
            trailing: switch (g.status) {
              GuestStatus.connecting => const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              GuestStatus.connected => const Icon(
                Icons.check_circle,
                color: Colors.green,
              ),
              GuestStatus.left => const Icon(Icons.cancel, color: Colors.red),
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Searches random opponents for 2–4 player games.
class RandomMatchScreen extends StatefulWidget {
  const RandomMatchScreen({super.key, required this.game, required this.size});
  final GameInfo game;
  final int size;

  @override
  State<RandomMatchScreen> createState() => _RandomMatchScreenState();
}

class _RandomMatchScreenState extends State<RandomMatchScreen> {
  RandomRoomSearch? _search;
  StreamSubscription<RoomSearchEvent>? _sub;
  RoomHost? _host;
  RoomGuest? _guest;
  String _status = 'Suche Mitspieler …';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.size == 2) {
      _findPair();
    } else {
      _findRoom();
    }
  }

  Future<void> _findPair() async {
    try {
      final match = await Services.I.matchmaker.findRandom(widget.game.id);
      if (!mounted) return;
      if (match.isHost) {
        final host = _newHost(widget.game, 2);
        _setHost(host);
        host.addGuest(match);
      } else {
        _join(match);
      }
    } on MatchmakingCancelled {
      // Screen closed.
    }
  }

  void _findRoom() {
    final search = RandomRoomSearch(
      Services.I.messenger,
      gameId: widget.game.id,
      size: widget.size,
      nameProvider: () => Services.I.account.name,
    );
    _search = search;
    _sub = search.events.listen((e) {
      if (!mounted) return;
      switch (e) {
        case HostingStarted():
          _setHost(_newHost(widget.game, widget.size));
          setState(() => _status = 'Warte auf Mitspieler …');
        case GuestJoined(:final match):
          _host?.addGuest(match);
        case JoinedRoom(:final match):
          _join(match);
      }
    });
    search.start();
  }

  void _setHost(RoomHost host) {
    _host = host;
    host.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (host.connected.length + 1 >= widget.size) _start();
    });
    setState(() => _status = 'Verbinde …');
  }

  Future<void> _join(MatchInfo match) async {
    final guest = RoomGuest(match, Services.I.createSession);
    _guest = guest;
    setState(
      () => _status = 'Verbunden mit ${match.opponentName}, warte auf Start …',
    );
    try {
      final room = await guest.room;
      _started = true;
      if (mounted) {
        openGameRoom(context, room);
      } else {
        room.close();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Der Host hat den Raum verlassen.');
      }
    }
  }

  void _start() {
    final host = _host;
    if (host == null || _started || !host.canStart) return;
    _started = true;
    _search?.cancel();
    final room = host.start();
    openGameRoom(context, room);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _search?.cancel();
    Services.I.matchmaker.cancelRandom();
    if (!_started) {
      _host?.close();
      _guest?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.game.title} – zufällig')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(widget.game.icon, size: 64, color: widget.game.color),
          const SizedBox(height: 16),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('${widget.size} Spieler', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          if (host != null) ...[
            const SizedBox(height: 16),
            _PlayerList(host: host),
            if (widget.size > 2)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton.icon(
                  onPressed: host.canStart ? _start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    'Jetzt mit ${host.connected.length + 1} Spielern starten',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

enum _InviteState { pending, accepted, declined }

/// Host a room and invite friends (up to the game's maximum).
class FriendsRoomScreen extends StatefulWidget {
  const FriendsRoomScreen({super.key, required this.game});
  final GameInfo game;

  @override
  State<FriendsRoomScreen> createState() => _FriendsRoomScreenState();
}

class _FriendsRoomScreenState extends State<FriendsRoomScreen> {
  late final RoomHost host = _newHost(
    widget.game,
    widget.game.maxOnlinePlayers,
  );
  final Map<String, _InviteState> _invites = {};
  final Map<String, String> _inviteIds = {};
  bool _started = false;

  @override
  void initState() {
    super.initState();
    host.addListener(_changed);
    Services.I.presence.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (widget.game.maxOnlinePlayers == 2 && host.connected.isNotEmpty) {
      _start();
    }
  }

  @override
  void dispose() {
    host.removeListener(_changed);
    Services.I.presence.removeListener(_changed);
    if (!_started) {
      for (final e in _invites.entries) {
        if (e.value == _InviteState.pending) {
          final id = _inviteIds[e.key];
          if (id != null) Services.I.matchmaker.cancelInvite(id);
        }
      }
      host.close();
    }
    super.dispose();
  }

  Future<void> _invite(String pubkey, String name) async {
    final mm = Services.I.matchmaker;
    setState(() => _invites[pubkey] = _InviteState.pending);
    final future = mm.inviteFriend(pubkey, name, widget.game.id);
    _inviteIds[pubkey] = mm.lastInviteId!;
    final match = await future;
    if (!mounted) return;
    setState(() {
      _invites[pubkey] = match == null
          ? _InviteState.declined
          : _InviteState.accepted;
    });
    if (match != null && !_started) host.addGuest(match);
  }

  void _start() {
    if (_started || !host.canStart) return;
    _started = true;
    final room = host.start();
    openGameRoom(context, room);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.I;
    final friends = [...services.account.friends]
      ..sort((a, b) {
        final oa = services.presence.isOnline(a.pubkey);
        final ob = services.presence.isOnline(b.pubkey);
        if (oa != ob) return oa ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final slotsLeft = !host.isFull;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.game.title} – mit Freunden')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Spieler (max. ${widget.game.maxOnlinePlayers})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _PlayerList(host: host),
          if (widget.game.maxOnlinePlayers > 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.icon(
                onPressed: host.canStart ? _start : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  'Spiel mit ${host.connected.length + 1} Spielern starten',
                ),
              ),
            ),
          const Divider(height: 32),
          Text(
            'Freunde einladen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Noch keine Freunde – füge sie unter „Konto & Freunde“ per Freundescode hinzu.',
              ),
            ),
          for (final f in friends)
            ListTile(
              leading: Icon(
                Icons.circle,
                size: 14,
                color: services.presence.isOnline(f.pubkey)
                    ? Colors.green
                    : Colors.grey,
              ),
              title: Text(f.name),
              trailing: switch (_invites[f.pubkey]) {
                _InviteState.pending => const Text('Eingeladen …'),
                _InviteState.accepted => const Icon(
                  Icons.check,
                  color: Colors.green,
                ),
                _InviteState.declined => TextButton(
                  onPressed: slotsLeft ? () => _invite(f.pubkey, f.name) : null,
                  child: const Text('Abgelehnt – erneut'),
                ),
                null => FilledButton.tonal(
                  onPressed: slotsLeft ? () => _invite(f.pubkey, f.name) : null,
                  child: const Text('Einladen'),
                ),
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Guest after accepting an invite: waits until the host starts.
class GuestWaitScreen extends StatefulWidget {
  const GuestWaitScreen({super.key, required this.match});
  final MatchInfo match;

  @override
  State<GuestWaitScreen> createState() => _GuestWaitScreenState();
}

class _GuestWaitScreenState extends State<GuestWaitScreen> {
  late final RoomGuest guest = RoomGuest(
    widget.match,
    Services.I.createSession,
  );
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    guest.room.then(
      (room) {
        _started = true;
        if (mounted) {
          openGameRoom(context, room);
        } else {
          room.close();
        }
      },
      onError: (Object _) {
        if (mounted) {
          setState(() => _error = 'Der Host hat den Raum verlassen.');
        }
      },
    );
  }

  @override
  void dispose() {
    if (!_started) guest.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = gameById(widget.match.gameId);
    return Scaffold(
      appBar: AppBar(title: Text(game?.title ?? 'Spiel')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (game != null) Icon(game.icon, size: 64, color: game.color),
              const SizedBox(height: 16),
              ValueListenableBuilder(
                valueListenable: guest.status,
                builder: (context, s, _) => Text(
                  _error ??
                      '${widget.match.opponentName}s Raum – warte, bis das Spiel startet …',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 16),
              if (_error == null) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
