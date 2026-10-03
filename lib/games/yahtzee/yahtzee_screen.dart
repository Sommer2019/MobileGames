import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/leaderboard.dart';
import '../../core/net/room.dart';
import '../../core/secrets.dart';
import '../../core/shake.dart';
import '../../core/sound.dart';
import '../../ui/dice.dart';
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

  bool get vsAi => widget.setup.kind == PlayKind.ai;
  final KniffelAi _ai = KniffelAi();
  bool _aiRunning = false;

  /// Secret "lucky computer": in one of its turns the computer's first
  /// roll is suspiciously good.
  final Random _rng = Random();
  int _aiTurn = 0;
  late int _luckyTurn = _pickLuckyTurn();
  int _pickLuckyTurn() => 2 + _rng.nextInt(9);

  /// Index of this device's player (online, or against the computer).
  /// The starting player alternates every round.
  int get me => vsAi
      ? round % 2
      : (widget.setup.mySeat - round % players + players) % players;

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
    _maybeAi();
  }

  /// Plays the computer's turn step by step so it can be followed.
  Future<void> _maybeAi() async {
    if (!vsAi || _aiRunning || game.isOver || game.currentPlayer == me) return;
    _aiRunning = true;
    Future<void> pause(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));
    await pause(600);
    while (mounted && !game.isOver && game.currentPlayer != me) {
      final heldBefore = List<bool>.from(game.held);
      final first = !game.hasRolled;
      if (first) _aiTurn++;
      final lucky =
          first && _aiTurn == _luckyTurn && Secrets.on(Secret.luckyComputer);
      Sound.play(Sfx.dice);
      setState(() {
        if (lucky) {
          game.applyRoll(List.filled(5, 1 + _rng.nextInt(6)));
        } else {
          game.roll();
        }
        _spin(heldBefore, first);
      });
      if (lucky && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🤨 Der Computer hat verdächtig gut gewürfelt …'),
          ),
        );
      }
      await pause(900);
      if (!mounted) break;
      final sheet = game.sheets[game.currentPlayer];
      if (game.canRoll) {
        final holds = _ai.chooseHolds(game.dice, sheet, game.rollsLeft);
        if (!holds.every((h) => h)) {
          setState(() => game.held = holds);
          await pause(700);
          continue;
        }
      }
      final (cat, _) = _ai.bestCategory(game.dice, sheet);
      setState(() => game.score(cat));
      await pause(500);
    }
    _aiRunning = false;
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

  bool get myTurn =>
      (!widget.setup.online && !vsAi) || game.currentPlayer == me;

  String playerName(int i) {
    final room = widget.setup.room;
    if (room != null) {
      return i == me ? 'Du' : room.names[(i + round) % players];
    }
    if (vsAi) return i == me ? 'Du' : 'Computer';
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
          Sound.play(Sfx.dice);
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
    Sound.play(Sfx.dice);
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
    if (game.isOver && players == 1 && widget.setup.kind == PlayKind.local) {
      Leaderboard.submit('kniffel', game.sheets[0].total);
    }
    _maybeAi();
  }

  void _rematch() {
    if (_aiRunning) return;
    setState(() {
      round++;
      game = KniffelGame(players);
      _aiTurn = 0;
      _luckyTurn = _pickLuckyTurn();
    });
    widget.setup.send({'t': 'rematch'});
    _maybeAi();
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
              aiWinBoard: Secrets.on(Secret.luckyComputer)
                  ? 'kniffel.lucky'
                  : null,
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
                  child: RollingDie(
                    key: ValueKey('die-$i'),
                    value: game.dice[i],
                    rollId: _spins[i],
                    held: game.held[i],
                    visible: game.hasRolled,
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
