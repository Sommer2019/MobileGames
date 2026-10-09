import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import '../../ui/bot_speed.dart';
import 'battleship_logic.dart';
import 'fleet_editor.dart';

enum _Phase { placing, waitingForOpponent, playing, over }

class BattleshipScreen extends StatefulWidget {
  const BattleshipScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<BattleshipScreen> createState() => _BattleshipScreenState();
}

class _BattleshipScreenState extends State<BattleshipScreen>
    with SavedGameState, GameMirror, SavedGameMirror {
  @override
  String? get mirrorGame => widget.setup.online ? null : 'battleship';

  @override
  Map<String, dynamic> get mirrorSetup => widget.setup.mirrorInfo;

  late FleetBoard fleet;
  late TargetBoard enemy;
  _Phase phase = _Phase.placing;
  bool myTurn = false;
  bool awaitingResult = false;
  bool opponentReady = false;
  bool? iWon;
  late int round = widget.setup.firstRound;
  String? lastEvent;

  // Computer opponent.
  FleetBoard? aiFleet;
  BattleshipAi? ai;

  StreamSubscription<RoomMessage>? _sub;

  bool get iStart => round.isEven == widget.setup.isHost;

  /// Only games against the computer are kept (on one device the other
  /// screen is used).
  @override
  String? get saveKey => widget.setup.kind == PlayKind.ai
      ? widget.setup.saveKey('battleship')
      : null;

  @override
  Map<String, dynamic>? saveGame() {
    if (phase != _Phase.playing) return null;
    return {
      'round': round,
      'myTurn': myTurn,
      'event': lastEvent,
      'fleet': fleet.toJson(),
      'enemy': enemy.toJson(),
      'aiFleet': aiFleet!.toJson(),
      'ai': ai!.knowledge.toJson(),
    };
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    _newRound();
    round = data['round'] as int;
    myTurn = data['myTurn'] as bool;
    lastEvent = data['event'] as String?;
    fleet = FleetBoard.fromJson(data['fleet'] as Map<String, dynamic>);
    enemy.load(data['enemy'] as List);
    aiFleet = FleetBoard.fromJson(data['aiFleet'] as Map<String, dynamic>);
    ai!.knowledge.load(data['ai'] as List);
    phase = _Phase.playing;
  }

  @override
  void initState() {
    super.initState();
    if (!restoredGame) _newRound();
    _sub = widget.setup.listen((m) => _onMessage(m.data));
    if (restoredGame && !myTurn) _aiTurn();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _newRound() {
    fleet = FleetBoard.random();
    enemy = TargetBoard();
    phase = _Phase.placing;
    awaitingResult = false;
    opponentReady = false;
    iWon = null;
    lastEvent = null;
    revealed = {};
    if (widget.setup.kind == PlayKind.ai) {
      aiFleet = FleetBoard.random();
      ai = BattleshipAi();
    }
  }

  void _ready() {
    setState(() {
      if (widget.setup.kind == PlayKind.ai) {
        phase = _Phase.playing;
        myTurn = round.isEven;
      } else {
        widget.setup.send({'t': 'ready'});
        phase = opponentReady ? _Phase.playing : _Phase.waitingForOpponent;
        myTurn = iStart;
      }
    });
    if (widget.setup.kind == PlayKind.ai && !myTurn) _aiTurn();
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'ready':
        setState(() {
          opponentReady = true;
          if (phase == _Phase.waitingForOpponent) phase = _Phase.playing;
        });
      case 'shot':
        final x = m['x'] as int, y = m['y'] as int;
        final o = fleet.receiveShot(x, y);
        widget.setup.send({'t': 'result', 'x': x, 'y': y, ...o.toJson()});
        setState(() {
          lastEvent = _describe(o, mine: false);
          if (o.fleetDestroyed) {
            _gameOver(false);
          } else if (o.result == ShotResult.miss) {
            myTurn = true;
          }
        });
      case 'result':
        final o = ShotOutcome.fromJson(m);
        setState(() {
          enemy.apply(m['x'] as int, m['y'] as int, o);
          awaitingResult = false;
          lastEvent = _describe(o, mine: true);
          if (o.fleetDestroyed) {
            _gameOver(true);
          } else if (o.result == ShotResult.miss) {
            myTurn = false;
          }
        });
      case 'reveal':
        setState(() {
          revealed = {
            for (final ship in m['ships'] as List)
              for (final c in ship as List)
                ((c as List)[0] as int, c[1] as int),
          };
        });
      case 'rematch':
        setState(() {
          round++;
          _newRound();
        });
    }
  }

  /// Cells of the opponent's ships, shown when the game is over.
  Set<(int, int)> revealed = {};

  void _gameOver(bool won) {
    phase = _Phase.over;
    iWon = won;
    if (widget.setup.kind == PlayKind.ai) {
      revealed = {for (final sh in aiFleet!.ships) ...sh.cells};
    }
    widget.setup.send({
      't': 'reveal',
      'ships': [
        for (final sh in fleet.ships)
          [
            for (final (x, y) in sh.cells) [x, y],
          ],
      ],
    });
  }

  String _describe(ShotOutcome o, {required bool mine}) {
    final who = mine ? 'Du' : _opponent;
    return switch (o.result) {
      ShotResult.miss => '$who: Wasser',
      ShotResult.hit => '$who: Treffer! Nochmal.',
      ShotResult.sunk => '$who: Versenkt! (${o.sunkCells.length}er)',
    };
  }

  String get _opponent =>
      widget.setup.kind == PlayKind.ai ? 'Computer' : widget.setup.opponentName;

  void _shoot(int x, int y) {
    if (phase != _Phase.playing ||
        !myTurn ||
        awaitingResult ||
        !enemy.canShoot(x, y)) {
      return;
    }
    Sound.play(Sfx.thud);
    if (widget.setup.kind == PlayKind.ai) {
      final o = aiFleet!.receiveShot(x, y);
      setState(() {
        enemy.apply(x, y, o);
        lastEvent = _describe(o, mine: true);
        if (o.fleetDestroyed) {
          _gameOver(true);
        } else if (o.result == ShotResult.miss) {
          myTurn = false;
        }
      });
      if (!myTurn && phase == _Phase.playing) _aiTurn();
    } else {
      setState(() => awaitingResult = true);
      widget.setup.send({'t': 'shot', 'x': x, 'y': y});
    }
  }

  Future<void> _aiTurn() async {
    if (widget.setup.spectator) return;
    while (mounted && phase == _Phase.playing && !myTurn) {
      await Future<void>.delayed(BotSpeed.ms(700));
      if (!mounted) return;
      final (x, y) = ai!.nextShot();
      final o = fleet.receiveShot(x, y);
      ai!.learn(x, y, o);
      setState(() {
        lastEvent = _describe(o, mine: false);
        if (o.fleetDestroyed) {
          _gameOver(false);
        } else if (o.result == ShotResult.miss) {
          myTurn = true;
        }
      });
    }
  }

  void _rematch({bool next = true}) {
    setState(() {
      if (next) round++;
      _newRound();
    });
    if (next) widget.setup.send({'t': 'rematch'});
    persistGame();
  }

  List<int> _winnerSeats() => [
    iWon == true ? widget.setup.mySeat : 1 - widget.setup.mySeat,
  ];

  String _status() {
    switch (phase) {
      case _Phase.placing:
        return 'Stelle deine Flotte auf';
      case _Phase.waitingForOpponent:
        return 'Warte auf $_opponent …';
      case _Phase.over:
        return iWon == true
            ? 'Gewonnen! Flotte versenkt 🎉'
            : '$_opponent hat gewonnen';
      case _Phase.playing:
        if (awaitingResult) return 'Schuss unterwegs …';
        return myTurn ? 'Dein Schuss!' : '$_opponent schießt …';
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Schiffe versenken',
      actions: [
        if (saveKey != null && phase != _Phase.placing)
          RestartButton(onRestart: () => _rematch(next: false)),
      ],
      child: Column(
        children: [
          TurnBanner(
            text: _status(),
            highlight:
                (phase == _Phase.playing && myTurn) || phase == _Phase.over,
          ),
          if (lastEvent != null)
            Text(lastEvent!, style: Theme.of(context).textTheme.bodyLarge),
          if (phase == _Phase.placing) ...[
            Expanded(
              child: FleetEditor(
                fleet: fleet,
                onChanged: (f) => setState(() => fleet = f),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                key: const ValueKey('fleetReady'),
                onPressed: fleetComplete(fleet) ? _ready : null,
                icon: const Icon(Icons.check),
                label: const Text('Bereit'),
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Gegnerisches Meer'),
            ),
            Expanded(flex: 3, child: _grid(own: false, interactive: true)),
            const Text('Deine Flotte'),
            Expanded(flex: 2, child: _grid(own: true, interactive: false)),
            if (phase == _Phase.over)
              GameOverActions(
                setup: widget.setup,
                winnerSeats: _winnerSeats(),
                onRematch: _rematch,
              ),
          ],
        ],
      ),
    );
  }

  Widget _grid({required bool own, required bool interactive}) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0D47A1),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(2),
          child: LayoutBuilder(
            builder: (context, c) {
              final size = min(c.maxWidth, c.maxHeight) / boardSize;
              return Column(
                children: [
                  for (var y = 0; y < boardSize; y++)
                    Row(
                      children: [
                        for (var x = 0; x < boardSize; x++)
                          SizedBox(
                            width: size,
                            height: size,
                            child: own
                                ? _ownCell(x, y)
                                : _enemyCell(x, y, interactive),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _ownCell(int x, int y) {
    final ship = fleet.shipAt(x, y);
    final shot = fleet.shotsReceived.contains((x, y));
    Color color = const Color(0xFF1976D2);
    if (ship != null) {
      color = ship.sunk ? const Color(0xFF4E342E) : const Color(0xFF90A4AE);
    }
    return Container(
      margin: const EdgeInsets.all(0.5),
      color: color,
      child: shot
          ? Center(
              child: Icon(
                ship != null ? Icons.local_fire_department : Icons.circle,
                size: ship != null ? null : 6,
                color: ship != null ? Colors.deepOrange : Colors.white70,
              ),
            )
          : null,
    );
  }

  Widget _enemyCell(int x, int y, bool interactive) {
    final s = enemy.cells[y][x];
    final hidden = s == TargetCell.unknown && revealed.contains((x, y));
    final (color, icon) = switch (s) {
      TargetCell.unknown when hidden => (
        const Color(0xFF78909C),
        Icons.visibility,
      ),
      TargetCell.unknown => (const Color(0xFF1976D2), null),
      TargetCell.miss => (const Color(0xFF1565C0), Icons.circle),
      TargetCell.hit => (const Color(0xFFFF7043), Icons.close),
      TargetCell.sunk => (const Color(0xFF4E342E), Icons.close),
    };
    return GestureDetector(
      key: ValueKey('bs$x-$y'),
      onTap: interactive ? () => _shoot(x, y) : null,
      child: Container(
        margin: const EdgeInsets.all(0.5),
        color: color,
        child: icon == null
            ? null
            : Icon(
                icon,
                size: s == TargetCell.miss ? 6 : (hidden ? 12 : null),
                color: Colors.white70,
              ),
      ),
    );
  }
}
