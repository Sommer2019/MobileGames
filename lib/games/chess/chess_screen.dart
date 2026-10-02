import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../ui/play_setup.dart';
import 'chess_logic.dart';

const _glyphs = {'K': '♚', 'Q': '♛', 'R': '♜', 'B': '♝', 'N': '♞', 'P': '♟'};

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  ChessGame game = ChessGame();
  int round = 0;
  String? selected;
  List<String> targets = const [];
  StreamSubscription<RoomMessage>? _sub;
  bool _aiThinking = false;

  /// The side this device plays. Colors swap every round.
  ChessSide get mySide {
    final hostWhite = round.isEven;
    final isHost = widget.setup.isHost;
    return (isHost == hostWhite) ? ChessSide.white : ChessSide.black;
  }

  bool get flipped =>
      widget.setup.kind != PlayKind.local && mySide == ChessSide.black;

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
            () => game.move(
              m['from'] as String,
              m['to'] as String,
              promotion: m['promo'] as String?,
            ),
          );
        }
      case 'rematch':
        _reset(send: false);
      case 'resign':
        setState(() => _resigned = 'opponent');
    }
  }

  String? _resigned;

  bool get _canMove {
    if (game.isOver || _resigned != null) return false;
    return switch (widget.setup.kind) {
      PlayKind.local => true,
      PlayKind.ai => game.turn == mySide && !_aiThinking,
      PlayKind.online => game.turn == mySide,
    };
  }

  Future<void> _tap(String sq) async {
    if (!_canMove) return;
    if (selected != null && targets.contains(sq)) {
      final from = selected!;
      String? promo;
      if (game.isPromotion(from, sq)) {
        promo = await _askPromotion();
        if (promo == null) return;
      }
      setState(() {
        game.move(from, sq, promotion: promo);
        selected = null;
        targets = const [];
      });
      widget.setup.send({'t': 'move', 'from': from, 'to': sq, 'promo': promo});
      _maybeAi();
      return;
    }
    if (game.colorAt(sq) == game.turn) {
      setState(() {
        selected = sq;
        targets = game.targets(sq);
      });
    } else {
      setState(() {
        selected = null;
        targets = const [];
      });
    }
  }

  Future<String?> _askPromotion() => showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Umwandeln in'),
      children: [
        for (final (p, name) in const [
          ('q', 'Dame'),
          ('r', 'Turm'),
          ('b', 'Läufer'),
          ('n', 'Springer'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, p),
            child: Text(
              '${_glyphs[p.toUpperCase()]}  $name',
              style: const TextStyle(fontSize: 20),
            ),
          ),
      ],
    ),
  );

  Future<void> _maybeAi() async {
    if (widget.setup.kind != PlayKind.ai ||
        game.isOver ||
        game.turn == mySide) {
      return;
    }
    setState(() => _aiThinking = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final m = game.aiMove();
    if (!mounted) return;
    setState(() {
      if (m != null) game.move(m.$1, m.$2, promotion: m.$3);
      _aiThinking = false;
    });
  }

  void _reset({bool send = true}) {
    setState(() {
      game = ChessGame();
      round++;
      selected = null;
      targets = const [];
      _resigned = null;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    _maybeAi();
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Aufgeben?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Nein'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Aufgeben'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _resigned = 'me');
    widget.setup.send({'t': 'resign'});
  }

  String _status() {
    if (_resigned == 'me') return 'Du hast aufgegeben';
    if (_resigned == 'opponent') {
      return '${widget.setup.opponentName} hat aufgegeben – du gewinnst!';
    }
    if (widget.setup.kind == PlayKind.local || game.isOver) {
      return game.statusText();
    }
    final mine = game.turn == mySide;
    final check = game.inCheck ? ' (Schach!)' : '';
    if (mine) return 'Du bist am Zug$check';
    return widget.setup.kind == PlayKind.ai
        ? 'Computer denkt nach …'
        : '${widget.setup.opponentName} ist am Zug$check';
  }

  @override
  Widget build(BuildContext context) {
    final over = game.isOver || _resigned != null;
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Schach',
      actions: [
        if (!over && widget.setup.kind != PlayKind.local)
          IconButton(
            onPressed: _resign,
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Aufgeben',
          ),
      ],
      child: Column(
        children: [
          TurnBanner(text: _status(), highlight: _canMove || over),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _board(),
                ),
              ),
            ),
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.replay),
                label: Text(
                  widget.setup.online
                      ? 'Revanche (Farben tauschen)'
                      : 'Neues Spiel',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _board() {
    final last = game.lastMove;
    return Column(
      children: [
        for (var row = 0; row < 8; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 8; col++)
                  Expanded(child: _square(row, col, last)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _square(int row, int col, (String, String)? last) {
    final file = flipped ? 7 - col : col;
    final rank = flipped ? row : 7 - row;
    final sq = ChessGame.square(file, rank);
    final light = (file + rank).isOdd;
    var color = light ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);
    if (last != null && (last.$1 == sq || last.$2 == sq)) {
      color = Color.alphaBlend(const Color(0x66F6F669), color);
    }
    if (sq == selected) {
      color = Color.alphaBlend(const Color(0x8833AA33), color);
    }
    final piece = game.pieceAt(sq);
    final isTarget = targets.contains(sq);
    final kingInCheck =
        game.inCheck &&
        piece != null &&
        piece.toUpperCase() == 'K' &&
        game.colorAt(sq) == game.turn;
    return GestureDetector(
      key: ValueKey('sq$sq'),
      onTap: () => _tap(sq),
      child: Container(
        color: kingInCheck
            ? Color.alphaBlend(const Color(0x99FF0000), color)
            : color,
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            alignment: Alignment.center,
            children: [
              if (piece != null)
                Text(
                  _glyphs[piece.toUpperCase()]!,
                  style: TextStyle(
                    fontSize: c.maxHeight * 0.78,
                    height: 1.0,
                    color: piece == piece.toUpperCase()
                        ? Colors.white
                        : Colors.black,
                    shadows: [
                      Shadow(
                        color: piece == piece.toUpperCase()
                            ? Colors.black
                            : Colors.white54,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              if (isTarget)
                Container(
                  width: c.maxWidth * (piece == null ? 0.3 : 0.9),
                  height: c.maxHeight * (piece == null ? 0.3 : 0.9),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: piece == null ? Colors.black26 : null,
                    border: piece != null
                        ? Border.all(color: Colors.black26, width: 4)
                        : null,
                  ),
                ),
              if (col == 0)
                Positioned(
                  left: 2,
                  top: 1,
                  child: Text(
                    '${rank + 1}',
                    style: TextStyle(
                      fontSize: c.maxHeight * 0.18,
                      color: Colors.black54,
                    ),
                  ),
                ),
              if (row == 7)
                Positioned(
                  right: 2,
                  bottom: 0,
                  child: Text(
                    ChessGame.files[file],
                    style: TextStyle(
                      fontSize: c.maxHeight * 0.18,
                      color: Colors.black54,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
