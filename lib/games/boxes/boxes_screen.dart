import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/play_setup.dart';
import 'boxes_logic.dart';

const boxColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
];

class BoxesScreen extends StatefulWidget {
  const BoxesScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<BoxesScreen> createState() => _BoxesScreenState();
}

class _BoxesScreenState extends State<BoxesScreen>
    with SavedGameState, GameMirror, SavedGameMirror, BotTurns {
  @override
  String? get mirrorGame => setup.online ? null : 'boxes';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  late int round = widget.setup.firstRound;
  late BoxesGame game = _newGame();
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  BoxesGame _newGame() => BoxesGame(players: players, first: round);

  @override
  String? get saveKey => setup.saveKey('boxes');

  @override
  Map<String, dynamic>? saveGame() {
    if (!savingForMirror && (game.isOver || game.moves.isEmpty)) return null;
    return {'round': round, 'moves': game.moves};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = BoxesGame.replay(
      players,
      BoxesGame.defaultSize(players),
      data['moves'] as List,
      first: round,
    );
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    scheduleBot();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  int? get seatToMove => game.isOver ? null : game.current;

  @override
  void botAct(int seat) {
    final ai = BoxesAi(random: _random, strong: Secrets.on(Secret.boxesPro));
    _draw(ai.move(game), seat);
  }

  void _onMessage(RoomMessage m) {
    switch (m.data['t']) {
      case 'line':
        // Only the player whose turn it is may draw.
        if (m.seat != game.current) return;
        final l = m.data['l'];
        if (l is int && game.canDraw(l)) {
          setState(() => game.draw(l));
          Sound.play(Sfx.place);
          scheduleBot();
        }
      case 'rematch':
        _reset(send: false);
    }
  }

  void _draw(int line, int seat) {
    if (!game.canDraw(line)) return;
    final before = game.scores[seat];
    setState(() => game.draw(line));
    Sound.play(game.scores[seat] > before ? Sfx.thud : Sfx.place);
    setup.sendAs(seat, {'t': 'line', 'l': line});
    persistGame();
    scheduleBot();
  }

  void _tapLine(int line) {
    if (game.isOver || !setup.humanControls(game.current)) return;
    _draw(line, game.current);
  }

  void _reset({bool send = true, bool swap = true}) {
    setState(() {
      if (swap) round++;
      game = _newGame();
    });
    if (send) setup.send({'t': 'rematch'});
    persistGame();
    scheduleBot();
  }

  String _status() {
    if (game.isOver) {
      final w = game.winners;
      if (w.length > 1) return 'Unentschieden!';
      final n = setup.seatName(w.single);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final n = setup.seatName(game.current);
    if (setup.isBot(game.current)) return '$n überlegt …';
    return n == 'Du' ? 'Du bist dran' : '$n ist dran';
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: setup,
      title: 'Käsekästchen',
      actions: [
        if (saveKey != null)
          RestartButton(onRestart: () => _reset(send: false, swap: false)),
      ],
      child: Column(
        children: [
          TurnBanner(
            text: _status(),
            highlight: game.isOver || setup.humanControls(game.current),
            color: boxColors[game.isOver ? game.winners.first : game.current]
                .withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (var p = 0; p < players; p++)
                  Chip(
                    avatar: CircleAvatar(backgroundColor: boxColors[p]),
                    label: Text('${setup.seatName(p)}: ${game.scores[p]}'),
                    side: p == game.current && !game.isOver
                        ? BorderSide(color: boxColors[p], width: 2)
                        : null,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AspectRatio(
                  aspectRatio: game.cols / game.rows,
                  child: LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      key: const ValueKey('boxesBoard'),
                      onTapUp: (d) {
                        final l = _lineAt(d.localPosition, box.biggest);
                        if (l != null) _tapLine(l);
                      },
                      child: CustomPaint(
                        size: box.biggest,
                        painter: _BoxesPainter(
                          game,
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (game.isOver)
            GameOverActions(
              setup: setup,
              winnerSeats: game.winners,
              onRematch: _reset,
            ),
        ],
      ),
    );
  }

  /// The open line nearest to a tap (within half a box).
  int? _lineAt(Offset p, Size size) {
    final cw = size.width / game.cols, ch = size.height / game.rows;
    int? best;
    var bestD = min(cw, ch) * 0.45;
    for (final l in game.openLines) {
      final (r, c) = game.position(l);
      final mid = game.isHorizontal(l)
          ? Offset((c + 0.5) * cw, r * ch)
          : Offset(c * cw, (r + 0.5) * ch);
      final d = (mid - p).distance;
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter(this.game, this.ink);
  final BoxesGame game;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / game.cols, ch = size.height / game.rows;
    // Owned boxes.
    for (var b = 0; b < game.owner.length; b++) {
      final o = game.owner[b];
      if (o < 0) continue;
      final r = b ~/ game.cols, c = b % game.cols;
      canvas.drawRect(
        Rect.fromLTWH(c * cw, r * ch, cw, ch).deflate(3),
        Paint()..color = boxColors[o].withValues(alpha: 0.45),
      );
    }
    // Lines: drawn ones solid, open ones faint.
    final last = game.moves.isEmpty ? -1 : game.moves.last;
    for (var l = 0; l < game.lineCount; l++) {
      final (r, c) = game.position(l);
      final a = Offset(c * cw, r * ch);
      final b = game.isHorizontal(l)
          ? Offset((c + 1) * cw, r * ch)
          : Offset(c * cw, (r + 1) * ch);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = game.lines[l] ? 5 : 2
        ..color = game.lines[l]
            ? (l == last ? const Color(0xFFFFB300) : ink)
            : ink.withValues(alpha: 0.12);
      canvas.drawLine(a, b, paint);
    }
    final dot = Paint()..color = ink;
    for (var r = 0; r <= game.rows; r++) {
      for (var c = 0; c <= game.cols; c++) {
        canvas.drawCircle(Offset(c * cw, r * ch), 5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => true;
}
