import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/dice.dart';
import '../../ui/play_setup.dart';
import 'schocken_logic.dart';

class SchockenScreen extends StatefulWidget {
  const SchockenScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<SchockenScreen> createState() => _SchockenScreenState();
}

class _SchockenScreenState extends State<SchockenScreen>
    with SavedGameState, GameMirror, SavedGameMirror, BotTurns {
  @override
  String? get mirrorGame => setup.online ? null : 'schocken';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  late int round = widget.setup.firstRound;
  late SchockenGame game = SchockenGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();
  final SchockenAi _ai = SchockenAi();

  /// Rotation counters per die; rolled dice spin.
  final List<int> _spins = List.filled(3, 0);

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  bool get _canStart => setup.runsGame;

  @override
  Duration get botDelay => const Duration(milliseconds: 750);

  @override
  String? get saveKey => setup.saveKey('schocken');

  @override
  Map<String, dynamic>? saveGame() {
    if (!savingForMirror && (game.isOver || !game.started)) return null;
    return {'round': round, 'events': game.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = SchockenGame.replay(players, data['events'] as List, first: round);
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    if (!restoredGame && _canStart) _act(['new'], 0);
    scheduleBot();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  int? get seatToMove => game.toMove;

  @override
  void botAct(int seat) => _act(_ai.choose(game, _random), seat);

  void _act(List event, int seat) {
    final before = List<bool>.from(game.held);
    final firstRoll = game.rolls == 0;
    if (!game.apply(event)) return;
    setup.sendAs(seat, {'t': 'e', 'e': event});
    _after(event, before, firstRoll);
  }

  void _after(List event, List<bool> heldBefore, bool firstRoll) {
    setState(() {
      if (event.first == 'r') {
        for (var i = 0; i < 3; i++) {
          if (firstRoll || !heldBefore[i]) _spins[i]++;
        }
      }
    });
    switch (event.first) {
      case 'r':
        Sound.play(Sfx.dice);
      case 't':
        Sound.play(Sfx.click);
      case 's':
        Sound.play(Sfx.thud);
    }
    persistGame();
    scheduleBot();
  }

  void _onMessage(RoomMessage m) {
    final d = m.data;
    switch (d['t']) {
      case 'e':
        final e = d['e'];
        if (e is! List || e.isEmpty) return;
        if (e.first == 'new' ? m.seat != 0 : m.seat != game.toMove) return;
        final before = List<bool>.from(game.held);
        final firstRoll = game.rolls == 0;
        if (game.apply(List.from(e))) _after(e, before, firstRoll);
      case 'again':
        if (_canStart && game.isOver) _act(['new'], 0);
    }
  }

  void _again() {
    if (_canStart) {
      if (!setup.online) {
        round++;
        game = SchockenGame(players: players, first: round);
      }
      _act(['new'], 0);
    } else {
      setup.send({'t': 'again'});
    }
  }

  bool get _myTurn {
    final c = game.toMove;
    return c != null && setup.humanControls(c);
  }

  void _roll() {
    if (!_myTurn || !game.canRoll) return;
    _act([
      'r',
      for (var i = 0; i < 3; i++)
        game.rolls > 0 && game.held[i] ? game.dice[i] : _random.nextInt(6) + 1,
    ], game.current);
  }

  String _name(int seat) => setup.seatName(seat);

  String _status() {
    if (!game.started) return 'Warte auf den Start …';
    if (game.isOver) {
      final l = game.loser!;
      final n = _name(l);
      return n == 'Du' ? 'Du hast verloren 🍺' : '$n hat verloren!';
    }
    final c = game.current;
    final n = _name(c);
    final left = game.maxRolls - game.rolls;
    final rolls = '$left ${left == 1 ? 'Wurf' : 'Würfe'}';
    if (!setup.humanControls(c)) return '$n ist dran …';
    return n == 'Du' ? 'Du bist dran – noch $rolls' : '$n ist dran – $rolls';
  }

  String? _lastRoundText() {
    final r = game.lastRound;
    if (r == null) return null;
    final who = _name(r.worst);
    final lids = r.lids == 1 ? '1 Deckel' : '${r.lids} Deckel';
    final how = r.bestThrow.isSchockAus
        ? '${_name(r.best)} wirft Schock aus – $who verliert die Hälfte!'
        : r.fromPot
        ? '$who bekommt $lids aus dem Topf (${r.bestThrow.name})'
        : '$who bekommt $lids von ${_name(r.best)} (${r.bestThrow.name})';
    return r.halfLost && !r.bestThrow.isSchockAus
        ? '$how – und verliert die Hälfte!'
        : how;
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastRoundText();
    return OnlineGameFrame(
      setup: setup,
      title: 'Schocken',
      actions: [
        if (saveKey != null)
          RestartButton(
            onRestart: () {
              game = SchockenGame(players: players, first: round);
              _act(['new'], 0);
            },
          ),
      ],
      child: !game.started
          ? const Center(child: Text('Warte auf den Start …'))
          : Column(
              children: [
                TurnBanner(text: _status(), highlight: _myTurn || game.isOver),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${game.halfName} · Topf: ${game.pot} Deckel',
                    key: const ValueKey('schockenPot'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (last != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      last,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(child: _table()),
                if (!game.isOver) ...[
                  _diceRow(),
                  if (game.rolls > 0)
                    Text(
                      game.currentThrow.name,
                      key: const ValueKey('schockenThrow'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  _buttons(),
                ] else
                  GameOverActions(
                    setup: setup,
                    winnerSeats: [
                      for (var p = 0; p < players; p++)
                        if (p != game.loser) p,
                    ],
                    onRematch: _again,
                  ),
              ],
            ),
    );
  }

  Widget _table() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final p in [
          for (var k = 0; k < players; k++) (game.order.first + k) % players,
        ])
          _playerTile(p, theme),
      ],
    );
  }

  Widget _playerTile(int p, ThemeData theme) {
    final result = game.results.where((r) => r.seat == p).firstOrNull;
    final turn = game.toMove == p;
    final out = !game.inHalf[p] || !game.active[p];
    final halves = game.halfLosers.where((l) => l == p).length;
    final String info;
    if (!game.inHalf[p]) {
      info = 'schaut zu';
    } else if (!game.active[p]) {
      info = 'raus – keine Deckel';
    } else if (result != null) {
      final n = result.rolls;
      info = '${result.result.name} ($n ${n == 1 ? 'Wurf' : 'Würfe'})';
    } else if (turn) {
      info = 'würfelt …';
    } else {
      info = '';
    }
    return Card(
      key: ValueKey('schockenSeat$p'),
      color: turn ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF5D4037),
          foregroundColor: Colors.white,
          child: Text('${game.lids[p]}'),
        ),
        title: Text(
          '${_name(p)}'
          '${p == game.starter && !game.isOver ? ' · fängt an' : ''}',
          style: TextStyle(
            fontWeight: turn ? FontWeight.bold : null,
            color: out ? theme.disabledColor : null,
          ),
        ),
        subtitle: Text(info),
        trailing: halves > 0
            ? Text('🍺' * halves, style: const TextStyle(fontSize: 18))
            : null,
      ),
    );
  }

  Widget _diceRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 4),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_myTurn && game.canHold) {
                  _act(['h', i], game.current);
                }
              },
              child: AspectRatio(
                aspectRatio: 1,
                child: RollingDie(
                  key: ValueKey('schockenDie$i'),
                  value: game.dice[i],
                  rollId: _spins[i],
                  held: game.held[i],
                  visible: game.rolls > 0,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buttons() {
    final mine = _myTurn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.icon(
            key: const ValueKey('schockenRoll'),
            onPressed: mine && game.canRoll ? _roll : null,
            icon: const Icon(Icons.casino),
            label: Text(game.rolls == 0 ? 'Würfeln' : 'Nochmal'),
          ),
          if (game.canTurn)
            OutlinedButton(
              key: const ValueKey('schockenTurn'),
              onPressed: mine ? () => _act(['t'], game.current) : null,
              child: const Text('6 6 → 1'),
            ),
          OutlinedButton(
            key: const ValueKey('schockenStop'),
            onPressed: mine && game.canStop
                ? () => _act(['s'], game.current)
                : null,
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }
}
