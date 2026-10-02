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
  ConnectFourGame game = ConnectFourGame();
  int round = 0;
  StreamSubscription<RoomMessage>? _sub;
  bool _aiThinking = false;

  static const colors = [
    Colors.transparent,
    Color(0xFFE53935),
    Color(0xFFFDD835),
  ];

  /// Which player (1 or 2) this device controls online. The starting player
  /// alternates every round.
  int get myPlayer {
    final hostStarts = round.isEven;
    final hostPlayer = hostStarts ? 1 : 2;
    return widget.setup.isHost ? hostPlayer : 3 - hostPlayer;
  }

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
      game = ConnectFourGame();
      round++;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    _maybeAi();
  }

  String _status() {
    String name(int p) {
      switch (widget.setup.kind) {
        case PlayKind.local:
          return p == 1 ? 'Rot' : 'Gelb';
        case PlayKind.ai:
          return p == humanPlayer ? 'Du' : 'Computer';
        case PlayKind.online:
          return p == myPlayer ? 'Du' : widget.setup.opponentName;
      }
    }

    if (game.draw) return 'Unentschieden!';
    if (game.winner != 0) {
      final n = name(game.winner);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final n = name(game.currentPlayer);
    return n == 'Du' ? 'Du bist am Zug' : '$n ist am Zug';
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
                aspectRatio: ConnectFourGame.columns / ConnectFourGame.rows,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E4FD8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < ConnectFourGame.columns; c++)
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('c4col$c'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _tap(c),
                            child: Column(
                              children: [
                                for (var r = 0; r < ConnectFourGame.rows; r++)
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
