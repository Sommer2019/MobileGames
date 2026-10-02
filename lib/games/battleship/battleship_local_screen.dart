import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'battleship_logic.dart';
import 'fleet_editor.dart';

/// Two players on one device ("pass and play"). Between turns a cover
/// screen hides the boards until the next player is ready.
class BattleshipLocalScreen extends StatefulWidget {
  const BattleshipLocalScreen({super.key});

  @override
  State<BattleshipLocalScreen> createState() => _BattleshipLocalScreenState();
}

class _BattleshipLocalScreenState extends State<BattleshipLocalScreen> {
  final fleets = [FleetBoard.random(), FleetBoard.random()];
  final targets = [TargetBoard(), TargetBoard()];
  int current = 0;
  bool placing = true;
  bool covered = true;
  int? winner;
  String? lastEvent;
  bool _turnOver = false;

  String _name(int p) => 'Spieler ${p + 1}';

  void _ready() => setState(() {
    covered = false;
    _turnOver = false;
  });

  void _donePlacing() {
    setState(() {
      if (current == 0) {
        current = 1;
      } else {
        current = 0;
        placing = false;
      }
      covered = true;
    });
  }

  void _shoot(int x, int y) {
    if (placing ||
        winner != null ||
        _turnOver ||
        !targets[current].canShoot(x, y)) {
      return;
    }
    final o = fleets[1 - current].receiveShot(x, y);
    Sound.play(o.result == ShotResult.miss ? Sfx.click : Sfx.thud);
    setState(() {
      targets[current].apply(x, y, o);
      lastEvent = switch (o.result) {
        ShotResult.miss => 'Wasser – ${_name(1 - current)} ist dran',
        ShotResult.hit => 'Treffer! Nochmal.',
        ShotResult.sunk => 'Versenkt! Nochmal.',
      };
      if (o.fleetDestroyed) {
        winner = current;
      } else if (o.result == ShotResult.miss) {
        _turnOver = true;
      }
    });
  }

  void _nextPlayer() => setState(() {
    current = 1 - current;
    covered = true;
    lastEvent = null;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schiffe versenken – 2 Spieler')),
      body: SafeArea(
        child: covered && winner == null
            ? PassDeviceCover(playerName: _name(current), onReady: _ready)
            : placing
            ? _placingView()
            : _battleView(),
      ),
    );
  }

  Widget _placingView() => Column(
    children: [
      TurnBanner(text: '${_name(current)}: Flotte aufstellen', highlight: true),
      Expanded(
        child: FleetEditor(
          key: ValueKey('editor$current'),
          fleet: fleets[current],
          onChanged: (f) => setState(() => fleets[current] = f),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: fleetComplete(fleets[current]) ? _donePlacing : null,
          icon: const Icon(Icons.check),
          label: const Text('Fertig'),
        ),
      ),
    ],
  );

  Widget _battleView() {
    final w = winner;
    return Column(
      children: [
        TurnBanner(
          text: w != null
              ? '${_name(w)} gewinnt! 🎉'
              : '${_name(current)} schießt',
          highlight: true,
        ),
        if (lastEvent != null) Text(lastEvent!),
        const Text('Gegnerisches Meer'),
        Expanded(
          flex: 3,
          child: _grid((x, y) => _targetCell(targets[current], x, y)),
        ),
        const Text('Deine Flotte'),
        Expanded(
          flex: 2,
          child: _grid((x, y) => _ownCell(fleets[current], x, y)),
        ),
        if (_turnOver && w == null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              onPressed: _nextPlayer,
              child: const Text('Weitergeben'),
            ),
          ),
        if (w != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Beenden'),
            ),
          ),
      ],
    );
  }

  Widget _grid(Widget Function(int x, int y) cell) => Center(
    child: AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(2),
        color: const Color(0xFF0D47A1),
        child: LayoutBuilder(
          builder: (context, c) {
            final size = min(c.maxWidth, c.maxHeight) / boardSize;
            return Column(
              children: [
                for (var y = 0; y < boardSize; y++)
                  Row(
                    children: [
                      for (var x = 0; x < boardSize; x++)
                        SizedBox(width: size, height: size, child: cell(x, y)),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _ownCell(FleetBoard fleet, int x, int y) {
    final ship = fleet.shipAt(x, y);
    final shot = fleet.shotsReceived.contains((x, y));
    return Container(
      margin: const EdgeInsets.all(0.5),
      color: ship == null
          ? const Color(0xFF1976D2)
          : ship.sunk
          ? const Color(0xFF4E342E)
          : const Color(0xFF90A4AE),
      child: shot
          ? Icon(
              ship != null ? Icons.local_fire_department : Icons.circle,
              size: ship != null ? null : 6,
              color: ship != null ? Colors.deepOrange : Colors.white70,
            )
          : null,
    );
  }

  Widget _targetCell(TargetBoard t, int x, int y) {
    final s = t.cells[y][x];
    // After the game: show where the opponent's ships were.
    final hidden =
        winner != null &&
        s == TargetCell.unknown &&
        fleets[1 - current].shipAt(x, y) != null;
    return GestureDetector(
      key: ValueKey('lbs$x-$y'),
      onTap: () => _shoot(x, y),
      child: Container(
        margin: const EdgeInsets.all(0.5),
        color: switch (s) {
          TargetCell.unknown when hidden => const Color(0xFF78909C),
          TargetCell.unknown => const Color(0xFF1976D2),
          TargetCell.miss => const Color(0xFF1565C0),
          TargetCell.hit => const Color(0xFFFF7043),
          TargetCell.sunk => const Color(0xFF4E342E),
        },
        child: switch (s) {
          TargetCell.unknown => null,
          TargetCell.miss => const Icon(
            Icons.circle,
            size: 6,
            color: Colors.white70,
          ),
          _ => const Icon(Icons.close, color: Colors.white70),
        },
      ),
    );
  }
}
