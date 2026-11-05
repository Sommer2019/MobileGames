import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/mirror.dart';
import '../../core/net/room.dart';
import '../../core/leaderboard.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import '../geo/regions.dart';
import '../geo/source_picker.dart';
import '../geo/street_view.dart';
import 'geoguess_logic.dart';
import 'my_places.dart';
import 'my_places_screen.dart';

class GeoGuessScreen extends StatefulWidget {
  const GeoGuessScreen({
    super.key,
    required this.setup,
    this.viewBuilder,
    this.controller,
    this.sources,
  });
  final PlaySetup setup;

  /// Replace the street pictures, the page and the sources (tests).
  final Widget Function()? viewBuilder;
  final StreetViewController? controller;
  final List<GeoSource>? sources;

  @override
  State<GeoGuessScreen> createState() => _GeoGuessScreenState();
}

class _GeoGuessScreenState extends State<GeoGuessScreen> with GameMirror {
  /// Friends may watch a game on this device (online: through the room).
  @override
  String? get mirrorGame => setup.online ? null : 'geoguess';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  @override
  Map<String, dynamic>? mirrorState() => {'events': game.events};

  @override
  void applyMirror(Map<String, dynamic> state) {
    final before = (game.views.length, game.phase);
    game = GeoGuessGame.replay(players, state['events'] as List);
    if ((game.views.length, game.phase) == before) return;
    // A new round or its result: show it like the player sees it.
    if (game.phase == GuessPhase.round) _view.show(game.views.last);
    if (game.phase == GuessPhase.reveal) {
      _view.show(game.views.last);
      _showResult();
    }
  }

  PlaySetup get setup => widget.setup;
  int get players => setup.players;
  int get me => setup.mySeat;
  bool get isHost => setup.isHost && !setup.spectator;
  bool get canAct => !setup.spectator;

  late final List<GeoSource> _available = widget.sources ?? availableSources;
  late GeoGuessGame game = GeoGuessGame(
    players: players,
    sources: widget.sources ?? defaultSources,
  );
  late final StreetViewController _view =
      widget.controller ?? StreetViewController();
  StreamSubscription<RoomMessage>? _sub;
  Timer? _tick;
  bool _busy = false;

  /// Host: the places saved on this device.
  List<GeoView> _myPlaces = [];

  @override
  void initState() {
    super.initState();
    _sub = setup.listen((m) {
      final e = m.data['e'];
      if (m.data['t'] != 'e' || e is! List || e.isEmpty) return;
      if (game.apply(List.from(e), m.seat)) _after(e);
    });
    if (isHost) _act(['cfg', _cfg()]);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (isHost) _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    final list = await MyPlaces.load();
    if (!mounted) return;
    setState(() => _myPlaces = list);
    if (list.isEmpty && game.own) _act(['cfg', _cfg(own: false)]);
  }

  Future<void> _managePlaces() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MyPlacesScreen(sources: game.sources),
      ),
    );
    await _loadPlaces();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    if (widget.controller == null) _view.dispose();
    super.dispose();
  }

  Map<String, dynamic> _cfg({
    int? rounds,
    int? sec,
    List<GeoSource>? src,
    bool? own,
  }) => {
    'rounds': rounds ?? game.rounds,
    'sec': sec ?? game.seconds,
    'src': [for (final s in src ?? game.sources) s.name],
    'own': own ?? game.own,
  };

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _act(List e) {
    if (!canAct || !game.apply(e, me)) return;
    setup.send({'t': 'e', 'e': e});
    _after(e);
  }

  void _after(List e) {
    switch (e.first) {
      case 'round':
        _view.show(game.views.last);
        Sound.play(Sfx.click);
      case 'guess':
        if (isHost && game.allGuessed) _reveal();
      case 'reveal':
        _showResult();
        Sound.play(Sfx.thud);
      case 'end':
        if (setup.kind == PlayKind.local && game.countsForLeaderboard) {
          Leaderboard.submit('geoguess', game.total(0));
        }
    }
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (!mounted || game.phase != GuessPhase.round) return;
    if (isHost && game.timeLeft(_now()) == 0) _reveal();
    setState(() {});
  }

  /// Host: finds a random place and starts the next round.
  Future<void> _nextRound() async {
    if (!isHost || _busy) return;
    // Own places first, each once per game; then random ones.
    if (game.own) {
      final played = {for (final v in game.views) '${v.source.name}:${v.id}'};
      final left = [
        for (final p in _myPlaces)
          if (!played.contains('${p.source.name}:${p.id}')) p,
      ];
      if (left.isNotEmpty) {
        final pick = left[Random().nextInt(left.length)];
        _act(['round', game.views.length, pick.toJson(), _now()]);
        return;
      }
    }
    setState(() => _busy = true);
    final (view, error) = await _view.random(game.sources);
    if (!mounted) return;
    setState(() => _busy = false);
    if (view == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? 'Kein Ort gefunden')));
      return;
    }
    _act(['round', game.views.length, view.toJson(), _now()]);
  }

  void _reveal() {
    if (!isHost || game.phase != GuessPhase.round) return;
    _act([
      'reveal',
      game.round,
      {
        for (final MapEntry(:key, :value)
            in (game.guesses[game.round] ?? {}).entries)
          '$key': [value.$1, value.$2],
      },
    ]);
  }

  Future<void> _guess() async {
    if (!canAct || game.hasGuessed(me)) return;
    final (point, error) = await _view.guess();
    if (!mounted) return;
    if (point == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? 'Fehler')));
      return;
    }
    _act(['guess', game.round, point.$1, point.$2]);
  }

  void _showResult() {
    final r = game.round;
    final v = game.views[r];
    _view.result(MapPin(v.lat, v.lng, '📍'), [
      for (final MapEntry(:key, :value) in (game.guesses[r] ?? {}).entries)
        MapPin(value.$1, value.$2, setup.seatName(key)),
    ]);
  }

  String _dist(int r, int p) {
    final d = game.distance(r, p);
    return d == null ? 'kein Tipp' : formatDistance(d);
  }

  String _clock(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------- setup

  Widget _setup() {
    final theme = Theme.of(context);
    String timeLabel(int s) => s == 0 ? 'ohne Limit' : '${s ~/ 60} min';
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!streetViewSupported)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Auf diesem Gerät gibt es kein Street View. '
                  'Spiel lieber am Handy, auf dem Mac oder im Browser.',
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Ihr seht alle dasselbe Straßenbild und tippt auf der Karte, '
              'wo es aufgenommen wurde. Je näher, desto mehr Punkte '
              '(bis 5000 pro Runde).',
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: Text('Runden: ${game.rounds}'),
                  subtitle: isHost
                      ? Slider(
                          key: const ValueKey('ggRounds'),
                          value: game.rounds.toDouble(),
                          min: 1,
                          max: GeoGuessGame.maxRounds.toDouble(),
                          divisions: GeoGuessGame.maxRounds - 1,
                          label: '${game.rounds}',
                          onChanged: (v) =>
                              _act(['cfg', _cfg(rounds: v.round())]),
                        )
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: Text('Zeit pro Runde: ${timeLabel(game.seconds)}'),
                  subtitle: isHost
                      ? Wrap(
                          spacing: 8,
                          children: [
                            for (final s in GeoGuessGame.timeChoices)
                              ChoiceChip(
                                label: Text(timeLabel(s)),
                                selected: game.seconds == s,
                                onSelected: (_) => _act(['cfg', _cfg(sec: s)]),
                              ),
                          ],
                        )
                      : null,
                ),
                SourcePicker(
                  available: _available,
                  selected: game.sources,
                  onChanged: isHost ? (s) => _act(['cfg', _cfg(src: s)]) : null,
                ),
                if (isHost)
                  SwitchListTile(
                    key: const ValueKey('ggOwn'),
                    secondary: const Icon(Icons.bookmark),
                    title: const Text('Eigene Orte spielen'),
                    subtitle: Text(
                      _myPlaces.isEmpty
                          ? 'Noch keine gespeichert'
                          : '${_myPlaces.length} gespeichert – danach '
                                'geht es zufällig weiter',
                    ),
                    value: game.own,
                    onChanged: _myPlaces.isEmpty
                        ? null
                        : (v) => _act(['cfg', _cfg(own: v)]),
                  )
                else if (game.own)
                  const ListTile(
                    leading: Icon(Icons.bookmark),
                    title: Text('Der Host spielt seine eigenen Orte'),
                  ),
                if (isHost)
                  ListTile(
                    key: const ValueKey('ggManagePlaces'),
                    leading: const Icon(Icons.add_location_alt),
                    title: const Text('Eigene Orte verwalten'),
                    subtitle: const Text(
                      'Orte auf der Karte oder am eigenen Standort sammeln',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _managePlaces,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (players == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                game.countsForLeaderboard
                    ? '🏅 Zählt für die Bestenliste'
                    : '🏅 Für die Bestenliste: ${GeoGuessGame.leaderboardRounds}'
                          ' Runden, keine eigenen Orte',
                key: const ValueKey('ggBoardHint'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          if (isHost)
            FilledButton.icon(
              key: const ValueKey('ggStart'),
              onPressed: _busy ? null : _nextRound,
              icon: _busy ? _spinner() : const Icon(Icons.play_arrow),
              label: Text(_busy ? 'Suche einen Ort …' : 'Los geht’s'),
            )
          else
            const Center(child: Text('Warte, bis der Host startet …')),
        ],
      ),
    );
  }

  static Widget _spinner() => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  // ------------------------------------------------------- round, reveal

  Widget _roundBar() {
    final left = game.timeLeft(_now());
    final guessed = [
      for (var p = 0; p < players; p++)
        if (game.hasGuessed(p)) p,
    ];
    final mine = game.hasGuessed(me);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (players > 1)
            Text(
              'Getippt: ${guessed.length}/$players',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('ggGuess'),
                  onPressed: canAct && !mine ? _guess : null,
                  icon: const Icon(Icons.place),
                  label: Text(mine ? 'Getippt – warte …' : 'Tipp abgeben'),
                ),
              ),
              if (isHost && players > 1) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('ggReveal'),
                  onPressed: _reveal,
                  child: const Text('Auflösen'),
                ),
              ],
            ],
          ),
          if (left != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⏱ ${_clock(left)}'),
            ),
        ],
      ),
    );
  }

  Widget _revealBar() {
    final r = game.round;
    final order = [
      for (var p = 0; p < players; p++) p,
    ]..sort((a, b) => game.roundPoints(r, b).compareTo(game.roundPoints(r, a)));
    final country = countryByCode[game.views[r].country]?.name;
    final where = country == null ? null : '📍 $country';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (where != null)
            Text(where, style: Theme.of(context).textTheme.titleSmall),
          for (final p in order)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(setup.seatName(p))),
                  Text(_dist(r, p)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '+${game.roundPoints(r, p)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (isHost)
            FilledButton.icon(
              key: const ValueKey('ggNext'),
              onPressed: _busy
                  ? null
                  : game.lastRound
                  ? () => _act(['end'])
                  : _nextRound,
              icon: _busy ? _spinner() : const Icon(Icons.skip_next),
              label: Text(
                _busy
                    ? 'Suche einen Ort …'
                    : game.lastRound
                    ? 'Zum Ergebnis'
                    : 'Nächste Runde',
              ),
            )
          else
            const Text('Der Host startet die nächste Runde.'),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- results

  Widget _results() {
    final theme = Theme.of(context);
    final order = [for (var p = 0; p < players; p++) p]
      ..sort((a, b) => game.total(b).compareTo(game.total(a)));
    final winners = game.winners();
    final name = setup.seatName(winners.first);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          TurnBanner(
            text: players == 1
                ? '${game.total(0)} von ${game.rounds * 5000} Punkten'
                : winners.length > 1
                ? 'Gleichstand! 🎉'
                : name == 'Du'
                ? 'Du gewinnst! 🏆'
                : '$name gewinnt! 🏆',
            highlight: true,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final (rank, p) in order.indexed)
                  Card(
                    child: ExpansionTile(
                      key: ValueKey('ggResult$p'),
                      leading: CircleAvatar(child: Text('${rank + 1}')),
                      title: Text(setup.seatName(p)),
                      trailing: Text(
                        '${game.total(p)}',
                        style: theme.textTheme.titleMedium,
                      ),
                      children: [
                        for (var r = 0; r < game.views.length; r++)
                          ListTile(
                            dense: true,
                            title: Text('Runde ${r + 1}'),
                            subtitle: Text(_dist(r, p)),
                            trailing: Text('${game.roundPoints(r, p)}'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          GameOverActions(
            setup: setup,
            winnerSeats: winners,
            rematchLabel: 'Neues Spiel',
            onRematch: () {
              if (isHost) {
                _act(['new']);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Der Host startet das nächste Spiel.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing =
        game.phase == GuessPhase.round || game.phase == GuessPhase.reveal;
    return OnlineGameFrame(
      setup: setup,
      title: 'Wo bin ich?',
      child: Column(
        children: [
          if (playing)
            TurnBanner(
              text:
                  'Runde ${game.round + 1}/${game.rounds} · '
                  '${game.total(me)} Punkte',
              highlight: game.phase == GuessPhase.round && !game.hasGuessed(me),
            ),
          Expanded(
            // Keeps the page when banner and bars come and go.
            key: const ValueKey('ggStage'),
            child: Stack(
              children: [
                // Always there, so the host can look for the next place.
                Positioned.fill(
                  child:
                      widget.viewBuilder?.call() ??
                      StreetView(
                        controller: _view,
                        sources: game.sources,
                        mode: StreetViewMode.guess,
                        // Setup and results lie on top of it.
                        interactive: playing,
                      ),
                ),
                if (game.phase == GuessPhase.setup)
                  Positioned.fill(child: _setup()),
                if (game.phase == GuessPhase.results)
                  Positioned.fill(child: _results()),
              ],
            ),
          ),
          if (game.phase == GuessPhase.round) _roundBar(),
          if (game.phase == GuessPhase.reveal) _revealBar(),
        ],
      ),
    );
  }
}
