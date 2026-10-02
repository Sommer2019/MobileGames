import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../ui/play_setup.dart';
import 'connect_four_logic.dart';

class ConnectFourScreen extends StatefulWidget {
  const ConnectFourScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<ConnectFourScreen> createState() => _ConnectFourScreenState();
}

class _ConnectFourScreenState extends State<ConnectFourScreen> {
  late ConnectFourGame game = ConnectFourGame(players: widget.setup.players);
  int round = 0;
  StreamSubscription<RoomMessage>? _sub;
  bool _aiThinking = false;

  static const colors = [
    Colors.transparent,
    Color(0xFFE53935),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
  ];
  static const colorNames = ['', 'Rot', 'Gelb', 'Grün', 'Lila'];

  int get players => widget.setup.players;

  /// Seat that plays player number [p] (1-based). The starting seat moves on
  /// every round.
  int seatOf(int p) => (p - 1 + round) % players;

  /// Which player number this device controls online.
  int get myPlayer =>
      (widget.setup.mySeat - round % players + players) % players + 1;

  /// In AI mode the human starts every even round.
  int get humanPlayer => round.isEven ? 1 : 2;

  @override
  void initState() {
    super.initState();
    _sub = widget.setup.listen((m) => _onMessage(m.data));
    _maybeAi();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'drop':
        if (game.currentPlayer != myPlayer) {
          setState(() => game.drop(m['col'] as int));
        }
      case 'rematch':
        _reset(send: false);
    }
  }

  bool get _myTurn {
    if (game.isOver) return false;
    switch (widget.setup.kind) {
      case PlayKind.local:
        return true;
      case PlayKind.ai:
        return game.currentPlayer == humanPlayer && !_aiThinking;
      case PlayKind.online:
        return game.currentPlayer == myPlayer;
    }
  }

  void _tap(int col) {
    if (!_myTurn || !game.canDrop(col)) return;
    setState(() => game.drop(col));
    widget.setup.send({'t': 'drop', 'col': col});
    _maybeAi();
  }

  Future<void> _maybeAi() async {
    if (widget.setup.kind != PlayKind.ai ||
        game.isOver ||
        game.currentPlayer == humanPlayer) {
      return;
    }
    setState(() => _aiThinking = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final col = ConnectFourAi().bestMove(game);
    setState(() {
      game.drop(col);
      _aiThinking = false;
    });
  }

  void _reset({bool send = true}) {
    setState(() {
      game = ConnectFourGame(players: players);
      round++;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    _maybeAi();
  }

  String _status() {
    String name(int p) {
      switch (widget.setup.kind) {
        case PlayKind.local:
          return colorNames[p];
        case PlayKind.ai:
          return p == humanPlayer ? 'Du' : 'Computer';
        case PlayKind.online:
          return p == myPlayer
              ? 'Du'
              : '${widget.setup.room!.names[seatOf(p)]} (${colorNames[p]})';
      }
    }

    if (game.draw) return 'Unentschieden!';
    if (game.winner != 0) {
      final n = name(game.winner);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final n = name(game.currentPlayer);
    final mine = widget.setup.online
        ? ' – du bist ${colorNames[myPlayer]}'
        : '';
    return n == 'Du' ? 'Du bist am Zug$mine' : '$n ist am Zug$mine';
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: widget.setup,
      title: '4 gewinnt',
      child: Column(
        children: [
          TurnBanner(
            text: _status(),
            highlight: _myTurn || game.isOver,
            color:
                colors[game.isOver
                        ? (game.winner == 0 ? 0 : game.winner)
                        : game.currentPlayer]
                    .withValues(alpha: 0.35),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: game.columns / game.rows,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E4FD8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < game.columns; c++)
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('c4col$c'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _tap(c),
                            child: Column(
                              children: [
                                for (var r = 0; r < game.rows; r++)
                                  Expanded(child: _cell(r, c)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (game.isOver)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.replay),
                label: Text(widget.setup.online ? 'Revanche' : 'Neues Spiel'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(int r, int c) {
    final v = game.board[r][c];
    final winning = game.winningCells.contains((r, c));
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: v == 0 ? Colors.white : colors[v],
            border: winning ? Border.all(color: Colors.white, width: 4) : null,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
