import 'dart:async';

import 'package:chess_vectors_flutter/chess_vectors_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'chess_logic.dart';

/// Vector chess piece for a letter (uppercase = white).
Widget chessPiece(String letter, double size) {
  final white = letter == letter.toUpperCase();
  return switch (letter.toUpperCase()) {
    'K' => white ? WhiteKing(size: size) : BlackKing(size: size),
    'Q' => white ? WhiteQueen(size: size) : BlackQueen(size: size),
    'R' => white ? WhiteRook(size: size) : BlackRook(size: size),
    'B' => white ? WhiteBishop(size: size) : BlackBishop(size: size),
    'N' => white ? WhiteKnight(size: size) : BlackKnight(size: size),
    _ => white ? WhitePawn(size: size) : BlackPawn(size: size),
  };
}

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> with SavedGameState {
  ChessGame game = ChessGame();
  late int round = widget.setup.firstRound;
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
  String? get saveKey => widget.setup.saveKey('chess');

  @override
  Map<String, dynamic>? saveGame() {
    final moves = game.moveList;
    if (game.isOver || _resigned != null || moves.isEmpty) return null;
    return {'round': round, 'moves': moves};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    game = ChessGame.fromMoves(data['moves'] as List);
    round = data['round'] as int;
  }

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
        if (widget.setup.spectator || game.turn != mySide) {
          Sound.play(Sfx.place);
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
    if (widget.setup.spectator) return false;
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
        Sound.play(Sfx.place);
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
            child: Row(
              children: [
                chessPiece(
                  game.turn == ChessSide.black ? p : p.toUpperCase(),
                  40,
                ),
                const SizedBox(width: 12),
                Text(name, style: const TextStyle(fontSize: 20)),
              ],
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
    final m = game.aiMove(null, Secrets.on(Secret.grandmaster));
    if (!mounted) return;
    setState(() {
      if (m != null) {
        game.move(m.$1, m.$2, promotion: m.$3);
        Sound.play(Sfx.place);
      }
      _aiThinking = false;
    });
  }

  void _reset({bool send = true, bool swap = true}) {
    setState(() {
      game = ChessGame();
      if (swap) round++;
      selected = null;
      targets = const [];
      _resigned = null;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    persistGame();
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

  List<int> _winnerSeats() {
    final me = widget.setup.mySeat, other = 1 - me;
    if (_resigned == 'me') return [other];
    if (_resigned == 'opponent') return [me];
    if (game.isCheckmate) {
      // The side to move is mated.
      return [game.turn == mySide ? other : me];
    }
    return [0, 1];
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
        if (saveKey != null)
          RestartButton(onRestart: () => _reset(send: false, swap: false)),
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
            GameOverActions(
              setup: widget.setup,
              aiWinBoard: Secrets.on(Secret.grandmaster)
                  ? 'chess.grandmaster'
                  : null,
              winnerSeats: _winnerSeats(),
              onRematch: _reset,
              rematchLabel: 'Revanche (Farben tauschen)',
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (piece != null) chessPiece(piece, c.maxHeight * 0.92),
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
