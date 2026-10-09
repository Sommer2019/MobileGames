import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/services.dart';
import '../../ui/play_setup.dart';
import '../../ui/room_screens.dart';
import '../registry.dart';
import 'tournament_logic.dart';

const tournamentId = 'tournament';

/// Pseudo game used for the tournament room (invites, lobby).
GameInfo tournamentInfo({int maxPlayers = 4}) => GameInfo(
  id: tournamentId,
  title: 'Turnier',
  description: 'Mehrere Spiele und Runden gegen Freunde',
  icon: Icons.emoji_events,
  color: const Color(0xFFF9A825),
  maxOnlinePlayers: maxPlayers,
  multiplayerBuilder: (s) => TournamentScreen(setup: s),
);

/// Host: choose games and rounds, then invite friends.
class TournamentSetupScreen extends StatefulWidget {
  const TournamentSetupScreen({super.key});

  @override
  State<TournamentSetupScreen> createState() => _TournamentSetupScreenState();
}

class _TournamentSetupScreenState extends State<TournamentSetupScreen> {
  final Set<String> selected = {'connect_four', 'chess'};
  int rounds = 2;

  List<GameInfo> get candidates =>
      games.where((g) => g.multiplayerBuilder != null).toList();

  int get maxPlayers => selected.isEmpty
      ? 2
      : selected
            .map((id) => gameById(id)!.maxOnlinePlayers)
            .reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final total = selected.length * rounds;
    return Scaffold(
      appBar: AppBar(title: const Text('Turnier erstellen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Icon(
                Icons.emoji_events,
                size: 64,
                color: Color(0xFFF9A825),
              ),
              const SizedBox(height: 8),
              Text('Spiele', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in candidates)
                    FilterChip(
                      key: ValueKey('tour-${g.id}'),
                      avatar: Icon(g.icon, size: 18),
                      label: Text(
                        g.maxOnlinePlayers > 2
                            ? '${g.title} (2–${g.maxOnlinePlayers})'
                            : g.title,
                      ),
                      selected: selected.contains(g.id),
                      onSelected: (v) => setState(
                        () => v ? selected.add(g.id) : selected.remove(g.id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Runden', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  for (var r = 1; r <= 5; r++)
                    ButtonSegment(value: r, label: Text('$r')),
                ],
                selected: {rounds},
                onSelectionChanged: (s) => setState(() => rounds = s.first),
              ),
              const SizedBox(height: 16),
              Text(
                selected.isEmpty
                    ? 'Wähle mindestens ein Spiel.'
                    : '$total Partien • jede Runde alle gewählten Spiele • '
                          'Sieg 3 Punkte, Unentschieden 1 Punkt',
              ),
              if (maxPlayers > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Mit mehr als 2 Spielern werden nur Spiele gespielt, die '
                    'so viele Spieler erlauben.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('tourInvite'),
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => FriendsRoomScreen(
                            game: tournamentInfo(maxPlayers: maxPlayers),
                            startOptions: {
                              'games': [
                                for (final g in candidates)
                                  if (selected.contains(g.id)) g.id,
                              ],
                              'rounds': rounds,
                            },
                          ),
                        ),
                      ),
                icon: const Icon(Icons.group_add),
                label: const Text('Freunde einladen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standings and match control. The host starts each match; everybody
/// records results locally (all devices see the same game state).
class TournamentScreen extends StatefulWidget {
  const TournamentScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  late final GameRoom room = widget.setup.room!;
  late final Tournament tournament;
  StreamSubscription<RoomMessage>? _sub;
  int _started = -1;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    final games = [
      for (final id in (room.options['games'] as List? ?? const []))
        if ((gameById(id as String)?.maxOnlinePlayers ?? 0) >= room.size) id,
    ];
    tournament = Tournament(
      games: games,
      rounds: room.options['rounds'] as int? ?? 1,
      players: room.size,
    );
    _sub = room.messagesWhere((m) => m.data['_s'] == 'tour').listen((m) {
      if (m.data['t'] == 'start') _openMatch(m.data['i'] as int);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    room.close();
    super.dispose();
  }

  void _leave() {
    if (_left) return;
    _left = true;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.settings.name == _routeName || r.isFirst);
    if (nav.canPop()) nav.pop();
  }

  static const _routeName = 'tournament';

  void _startNext() {
    final i = tournament.nextMatch;
    room.send({'_s': 'tour', 't': 'start', 'i': i});
    _openMatch(i);
  }

  void _openMatch(int i) {
    if (i < 0 || i >= tournament.matchCount || i <= _started || !mounted) {
      return;
    }
    setState(() => _started = i);
    final game = gameById(tournament.schedule[i])!;
    // Friends can watch this game (not the standings).
    if (Services.isReady) {
      Services.I.spectators.attach(
        room,
        game: game.id,
        scope: 'm$i',
        firstRound: i,
      );
    }
    final nav = Navigator.of(context);
    // Close a previous game screen that is still open.
    nav.popUntil((r) => r.settings.name == _routeName || r.isFirst);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => game.multiplayerBuilder!(
          PlaySetup.online(
            room,
            scope: 'm$i',
            firstRound: i,
            onFinished: (winners) {
              if (mounted) setState(() => tournament.record(i, winners));
            },
            onLeave: _leave,
          ),
        ),
      ),
    );
  }

  String _name(int seat) => room.nameOf(seat);

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final ranking = t.ranking();
    final next = t.nextMatch;
    final waitingForResult = _started >= next && !t.finished;
    return OnlineGameFrame(
      setup: PlaySetup.online(room, onFinished: (_) {}, onLeave: _leave),
      title: 'Turnier',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (t.matchCount == 0)
            const Text('Keines der gewählten Spiele passt zur Spielerzahl.'),
          if (t.finished && t.matchCount > 0) ...[
            const Icon(Icons.emoji_events, size: 72, color: Color(0xFFF9A825)),
            Text(
              t.leaders().length > 1
                  ? 'Gleichstand an der Spitze: ${t.leaders().map(_name).join(', ')}'
                  : t.leaders().first == room.mySeat
                  ? 'Du hast das Turnier gewonnen! 🏆'
                  : '${_name(t.leaders().first)} gewinnt das Turnier! 🏆',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
          ],
          Text('Tabelle', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                for (var place = 0; place < ranking.length; place++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${place + 1}')),
                    title: Text(_name(ranking[place])),
                    subtitle: Text('${t.wins[ranking[place]]} Siege'),
                    trailing: Text(
                      '${t.points[ranking[place]]} P',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!t.finished && t.matchCount > 0) ...[
            Text(
              'Partie ${next + 1} von ${t.matchCount}: '
              '${gameById(t.schedule[next])!.title}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (room.isHost)
              FilledButton.icon(
                key: const ValueKey('tourNext'),
                onPressed: waitingForResult ? null : _startNext,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  waitingForResult ? 'Partie läuft …' : 'Partie starten',
                ),
              )
            else
              Text(
                waitingForResult
                    ? 'Partie läuft …'
                    : 'Warte, bis ${room.names[0]} die nächste Partie startet …',
              ),
          ],
          const SizedBox(height: 16),
          Text('Spielplan', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < t.matchCount; i++)
            ListTile(
              dense: true,
              leading: Icon(gameById(t.schedule[i])!.icon),
              title: Text('${i + 1}. ${gameById(t.schedule[i])!.title}'),
              trailing: Text(switch (t.results[i]) {
                null => i == next ? 'als Nächstes' : '',
                final w when w.length >= room.size => 'Unentschieden',
                final w => w.map(_name).join(', '),
              }),
            ),
        ],
      ),
    );
  }
}

/// Route settings so tournament screens can be found in the stack.
RouteSettings tournamentRouteSettings() =>
    const RouteSettings(name: _TournamentScreenState._routeName);
