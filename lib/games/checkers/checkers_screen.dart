import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../ui/play_setup.dart';
import 'checkers_logic.dart';

class CheckersScreen extends StatefulWidget {
  const CheckersScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<CheckersScreen> createState() => _CheckersScreenState();
}

class _CheckersScreenState extends State<CheckersScreen> {
  CheckersGame game = CheckersGame();
  late int round = widget.setup.firstRound;
  List<(int, int)> _partial = [];
  StreamSubscription<RoomMessage>? _sub;
  bool _aiThinking = false;

  /// Colors swap every round; the host starts with white.
  Side get mySide =>
      (widget.setup.isHost == round.isEven) ? Side.white : Side.black;

  bool get flipped =>
      widget.setup.kind != PlayKind.local && mySide == Side.black;

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
      case 'move':
        if (game.turn != mySide) {
          setState(
            () => game.playPath(
              CheckersMove.pathFromJson(m['path'] as List<dynamic>),
            ),
          );
        }
      case 'rematch':
        _reset(send: false);
    }
  }

  bool get _canMove {
    if (game.isOver) return false;
    return switch (widget.setup.kind) {
      PlayKind.local => true,
      PlayKind.ai => game.turn == mySide && !_aiThinking,
      PlayKind.online => game.turn == mySide,
    };
  }

  List<CheckersMove> get _candidates {
    final moves = game.legalMoves();
    return moves.where((m) {
      if (m.path.length < _partial.length) return false;
      for (var i = 0; i < _partial.length; i++) {
        if (m.path[i] != _partial[i]) return false;
      }
      return true;
    }).toList();
  }

  /// Squares the selected piece can go to next.
  Set<(int, int)> get _nextSquares {
    if (_partial.isEmpty) return const {};
    return {
      for (final m in _candidates)
        if (m.path.length > _partial.length) m.path[_partial.length],
    };
  }

  Set<(int, int)> get _movable => {for (final m in game.legalMoves()) m.from};

  void _tap(int r, int c) {
    if (!_canMove) return;
    final sq = (r, c);
    if (_partial.isNotEmpty && _nextSquares.contains(sq)) {
      setState(() => _partial = [..._partial, sq]);
      final remaining = _candidates;
      final done = remaining.where((m) => m.path.length == _partial.length);
      if (done.isNotEmpty && remaining.length == done.length) {
        _play(done.first);
      }
      return;
    }
    setState(() => _partial = _movable.contains(sq) ? [sq] : []);
  }

  void _play(CheckersMove m) {
    setState(() {
      game.playPath(m.path);
      _partial = [];
    });
    widget.setup.send({'t': 'move', 'path': m.toJson()});
    _maybeAi();
  }

  Future<void> _maybeAi() async {
    if (widget.setup.kind != PlayKind.ai ||
        game.isOver ||
        game.turn == mySide) {
      return;
    }
    setState(() => _aiThinking = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final m = game.aiMove();
    setState(() {
      if (m != null) game.playPath(m.path);
      _aiThinking = false;
    });
  }

  void _reset({bool send = true}) {
    setState(() {
      game = CheckersGame();
      round++;
      _partial = [];
    });
    if (send) widget.setup.send({'t': 'rematch'});
    _maybeAi();
  }

  String _sideName(Side s) => s == Side.white ? 'Weiß' : 'Schwarz';

  /// Seat that plays white this round.
  int get _whiteSeat => round.isEven ? 0 : 1;

  List<int> _winnerSeats() {
    final w = game.winner;
    if (w == null) return [0, 1];
    return [w == Side.white ? _whiteSeat : 1 - _whiteSeat];
  }

  String _status() {
    if (game.draw) return 'Remis';
    final w = game.winner;
    if (w != null) {
      if (widget.setup.kind == PlayKind.local) {
        return '${_sideName(w)} gewinnt!';
      }
      return w == mySide ? 'Du hast gewonnen! 🎉' : '${_opponent()} gewinnt';
    }
    final capture = game.legalMoves().any((m) => m.isCapture)
        ? ' – Schlagpflicht!'
        : '';
    if (widget.setup.kind == PlayKind.local) {
      return '${_sideName(game.turn)} ist am Zug$capture';
    }
    return game.turn == mySide
        ? 'Du bist am Zug (${_sideName(mySide)})$capture'
        : '${_opponent()} ist am Zug';
  }

  String _opponent() =>
      widget.setup.kind == PlayKind.ai ? 'Computer' : widget.setup.opponentName;

  @override
  Widget build(BuildContext context) {
    final next = _nextSquares;
    final movable = _canMove ? _movable : const <(int, int)>{};
    final last = game.lastMove;
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Dame',
      child: Column(
        children: [
          TurnBanner(text: _status(), highlight: _canMove || game.isOver),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF5D4037),
                      width: 6,
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var row = 0; row < 8; row++)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var col = 0; col < 8; col++)
                                Expanded(
                                  child: _square(
                                    flipped ? 7 - row : row,
                                    flipped ? 7 - col : col,
                                    next,
                                    movable,
                                    last,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (game.isOver)
            GameOverActions(
              setup: widget.setup,
              winnerSeats: _winnerSeats(),
              onRematch: _reset,
            ),
        ],
      ),
    );
  }

  Widget _square(
    int r,
    int c,
    Set<(int, int)> next,
    Set<(int, int)> movable,
    CheckersMove? last,
  ) {
    final dark = (r + c).isOdd;
    var color = dark ? const Color(0xFF8D6E63) : const Color(0xFFEFE0C8);
    if (last != null && (last.from == (r, c) || last.to == (r, c))) {
      color = Color.alphaBlend(const Color(0x55FFEB3B), color);
    }
    if (_partial.contains((r, c))) {
      color = Color.alphaBlend(const Color(0x8833AA33), color);
    }
    final p = game.board[r][c];
    final isNext = next.contains((r, c));
    return GestureDetector(
      key: ValueKey('ck$r-$c'),
      onTap: () => _tap(r, c),
      child: Container(
        color: color,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            alignment: Alignment.center,
            children: [
              if (p != null &&
                  !(_partial.length > 1 && _partial.first == (r, c)))
                Container(
                  width: box.maxWidth * 0.78,
                  height: box.maxWidth * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.side == Side.white
                        ? const Color(0xFFFAFAFA)
                        : const Color(0xFF212121),
                    border: Border.all(
                      color: movable.contains((r, c)) && _partial.isEmpty
                          ? Colors.greenAccent
                          : Colors.black45,
                      width: movable.contains((r, c)) && _partial.isEmpty
                          ? 3
                          : 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 2,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: p.king
                      ? Icon(
                          Icons.star,
                          size: box.maxWidth * 0.45,
                          color: p.side == Side.white
                              ? Colors.amber.shade700
                              : Colors.amber,
                        )
                      : null,
                ),
              if (isNext)
                Container(
                  width: box.maxWidth * 0.3,
                  height: box.maxWidth * 0.3,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black38,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
