import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/net/room.dart';
import '../../core/shake.dart';
import '../../ui/play_setup.dart';
import 'yahtzee_logic.dart';

class YahtzeeScreen extends StatefulWidget {
  const YahtzeeScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<YahtzeeScreen> createState() => _YahtzeeScreenState();
}

class _YahtzeeScreenState extends State<YahtzeeScreen> {
  late KniffelGame game;
  late int round = widget.setup.firstRound;
  StreamSubscription<RoomMessage>? _sub;

  int get players => widget.setup.players;

  /// Online: index of this device's player. The starting player alternates.
  int get me => (widget.setup.mySeat - round % players + players) % players;

  @override
  void initState() {
    super.initState();
    game = KniffelGame(players);
    _sub = widget.setup.listen((m) => _onMessage(m.data));
    _shake = ShakeDetector.listen(() {
      if (mounted && myTurn && game.canRoll) {
        HapticFeedback.mediumImpact();
        _roll();
      }
    });
  }

  StreamSubscription<Object?>? _shake;

  /// Rotation counters per die; rolled dice spin.
  final List<int> _spins = List.filled(5, 0);

  void _spin(List<bool> heldBefore, bool firstRoll) {
    for (var i = 0; i < 5; i++) {
      if (firstRoll || !heldBefore[i]) _spins[i]++;
    }
  }

  @override
  void dispose() {
    _shake?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  bool get myTurn => !widget.setup.online || game.currentPlayer == me;

  String playerName(int i) {
    final room = widget.setup.room;
    if (room != null) {
      return i == me ? 'Du' : room.names[(i + round) % players];
    }
    if (players == 1) return 'Du';
    return 'Spieler ${i + 1}';
  }

  void _onMessage(Map<String, dynamic> m) {
    if (game.currentPlayer == me && m['t'] != 'rematch') return;
    setState(() {
      switch (m['t']) {
        case 'roll':
          final heldBefore = List<bool>.from(game.held);
          final first = !game.hasRolled;
          game.applyRoll([for (final d in m['dice'] as List) d as int]);
          _spin(heldBefore, first);
        case 'hold':
          game.held = [for (final h in m['held'] as List) h as bool];
        case 'score':
          game.score(KniffelCategory.values.byName(m['cat'] as String));
        case 'rematch':
          round++;
          game = KniffelGame(players);
      }
    });
  }

  void _roll() {
    if (!myTurn || !game.canRoll) return;
    final heldBefore = List<bool>.from(game.held);
    final first = !game.hasRolled;
    setState(() {
      game.roll();
      _spin(heldBefore, first);
    });
    widget.setup.send({'t': 'roll', 'dice': game.dice});
  }

  void _hold(int i) {
    if (!myTurn) return;
    setState(() => game.toggleHold(i));
    widget.setup.send({'t': 'hold', 'held': game.held});
  }

  void _score(KniffelCategory c) {
    if (!myTurn || !game.canScore(c)) return;
    setState(() => game.score(c));
    widget.setup.send({'t': 'score', 'cat': c.name});
  }

  void _rematch() {
    setState(() {
      round++;
      game = KniffelGame(players);
    });
    widget.setup.send({'t': 'rematch'});
  }

  String _status() {
    if (game.isOver) {
      final w = game.winners();
      if (w.length > 1) {
        return 'Unentschieden mit ${game.sheets[w.first].total} Punkten';
      }
      final n = playerName(w.first);
      return n == 'Du'
          ? 'Du gewinnst mit ${game.sheets[w.first].total} Punkten! 🎉'
          : '$n gewinnt!';
    }
    final n = playerName(game.currentPlayer);
    final rolls =
        'noch ${game.rollsLeft} ${game.rollsLeft == 1 ? 'Wurf' : 'Würfe'}';
    return n == 'Du' ? 'Du bist dran – $rolls' : '$n ist dran – $rolls';
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Kniffel',
      child: Column(
        children: [
          TurnBanner(text: _status(), highlight: myTurn || game.isOver),
          _diceRow(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('rollButton'),
                    onPressed: myTurn && game.canRoll ? _roll : null,
                    icon: const Icon(Icons.casino),
                    label: Text(game.hasRolled ? 'Nochmal würfeln' : 'Würfeln'),
                  ),
                ),
              ],
            ),
          ),
          if (game.isOver)
            GameOverActions(
              setup: widget.setup,
              winnerSeats: [
                for (final i in game.winners()) (i + round) % players,
              ],
              onRematch: _rematch,
            ),
          if (myTurn && game.canRoll)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '📳 oder Handy schütteln',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _sheet()),
        ],
      ),
    );
  }

  Widget _diceRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => _hold(i),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: game.held[i]
                          ? Colors.amber.shade200
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: game.held[i]
                            ? Colors.amber.shade800
                            : Colors.black26,
                        width: game.held[i] ? 3 : 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: game.hasRolled
                        ? AnimatedRotation(
                            turns: _spins[i].toDouble(),
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutBack,
                            child: CustomPaint(
                              painter: _DiePainter(game.dice[i]),
                              size: Size.infinite,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sheet() {
    final theme = Theme.of(context);
    final current = game.currentPlayer;
    TableRow row(String label, List<Widget> cells, {bool bold = false}) =>
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(
                label,
                style: bold
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
              ),
            ),
            ...cells,
          ],
        );

    Widget cell(int p, KniffelCategory c) {
      final sheet = game.sheets[p];
      final filled = sheet.entries[c];
      final selectable = p == current && myTurn && game.canScore(c);
      return InkWell(
        key: ValueKey('score-$p-${c.name}'),
        onTap: selectable ? () => _score(c) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          color: selectable
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
              : null,
          child: Text(
            filled != null
                ? '$filled'
                : (selectable ? '${scoreFor(c, game.dice)}' : ''),
            style: TextStyle(
              fontWeight: filled != null ? FontWeight.bold : FontWeight.normal,
              color: filled != null ? null : theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    Widget total(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Table(
        border: TableBorder.all(color: theme.dividerColor),
        columnWidths: const {0: FlexColumnWidth(2.2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          row('', [
            for (var p = 0; p < players; p++)
              Container(
                color: p == current && !game.isOver
                    ? theme.colorScheme.secondaryContainer
                    : null,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  playerName(p),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ]),
          for (final c in KniffelCategory.values.where((c) => c.isUpper))
            row(c.label, [for (var p = 0; p < players; p++) cell(p, c)]),
          row('Bonus (ab 63)', [
            for (var p = 0; p < players; p++) total('${game.sheets[p].bonus}'),
          ], bold: true),
          for (final c in KniffelCategory.values.where((c) => !c.isUpper))
            row(c.label, [for (var p = 0; p < players; p++) cell(p, c)]),
          row('Gesamt', [
            for (var p = 0; p < players; p++) total('${game.sheets[p].total}'),
          ], bold: true),
        ],
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  _DiePainter(this.value);
  final int value;

  static const _pips = {
    1: [(0.5, 0.5)],
    2: [(0.25, 0.25), (0.75, 0.75)],
    3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
    6: [
      (0.25, 0.22),
      (0.75, 0.22),
      (0.25, 0.5),
      (0.75, 0.5),
      (0.25, 0.78),
      (0.75, 0.78),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    for (final (x, y) in _pips[value]!) {
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        size.width * 0.09,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.value != value;
}
