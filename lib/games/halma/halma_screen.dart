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
import 'halma_logic.dart';

/// Colours by arm.
const halmaColors = [
  Color(0xFFE53935),
  Color(0xFFFDD835),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFFB8C00),
];
const halmaColorNames = ['Rot', 'Gelb', 'Blau', 'Grün', 'Lila', 'Orange'];

class HalmaScreen extends StatefulWidget {
  const HalmaScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<HalmaScreen> createState() => _HalmaScreenState();
}

class _HalmaScreenState extends State<HalmaScreen>
    with
        SavedGameState,
        GameMirror,
        SavedGameMirror,
        BotTurns,
        TickerProviderStateMixin {
  @override
  String? get mirrorGame => setup.online ? null : 'halma';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  late int round = widget.setup.firstRound;
  late HalmaGame game = HalmaGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();

  int? _selected;
  Map<int, List<int>> _targets = const {};

  /// The last move, animated hop by hop.
  List<int>? _path;
  int? _pathPlayer;
  late final AnimationController _hop = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) scheduleBot();
    });

  /// Rainbow (secret): colours keep cycling.
  late final AnimationController _rainbow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  @override
  String? get saveKey => setup.saveKey('halma');

  @override
  Map<String, dynamic>? saveGame() {
    if (!savingForMirror && (game.isOver || game.moves.isEmpty)) return null;
    return {'round': round, 'moves': game.moves};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = HalmaGame.replay(players, data['moves'] as List, first: round);
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    if (Secrets.on(Secret.halmaRainbow)) _rainbow.repeat();
    scheduleBot();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hop.dispose();
    _rainbow.dispose();
    super.dispose();
  }

  @override
  int? get seatToMove => game.isOver || _hop.isAnimating ? null : game.current;

  @override
  void botAct(int seat) => _move(HalmaAi(_random).choose(game), seat);

  void _onMessage(RoomMessage m) {
    switch (m.data['t']) {
      case 'move':
        if (m.seat != game.current) return;
        final p = m.data['p'];
        if (p is! List || p.any((c) => c is! int)) return;
        _apply(List<int>.from(p));
      case 'rematch':
        _reset(send: false);
    }
  }

  void _move(List<int> path, int seat) {
    if (!game.isValid(path)) return;
    setup.sendAs(seat, {'t': 'move', 'p': path});
    _apply(path);
  }

  void _apply(List<int> path) {
    final player = game.current;
    if (!game.move(path)) return;
    setState(() {
      _selected = null;
      _targets = const {};
      _path = path;
      _pathPlayer = player;
    });
    _hop
      ..duration = Duration(milliseconds: 200 * (path.length - 1))
      ..forward(from: 0);
    Sound.play(path.length > 2 ? Sfx.clack : Sfx.place);
    persistGame();
    scheduleBot();
  }

  void _tap(int cell) {
    if (game.isOver || _hop.isAnimating) return;
    if (!setup.humanControls(game.current)) return;
    final path = _targets[cell];
    if (path != null) {
      _move(path, game.current);
      return;
    }
    setState(() {
      if (game.owner[cell] == game.current && cell != _selected) {
        _selected = cell;
        _targets = game.destinations(cell);
      } else {
        _selected = null;
        _targets = const {};
      }
    });
  }

  void _reset({bool send = true, bool swap = true}) {
    setState(() {
      if (swap) round++;
      game = HalmaGame(players: players, first: round);
      _selected = null;
      _targets = const {};
      _path = null;
    });
    if (send) setup.send({'t': 'rematch'});
    persistGame();
    scheduleBot();
  }

  String _name(int p) =>
      '${setup.seatName(p)} (${halmaColorNames[game.homes[p]]})';

  String _status() {
    if (game.isOver) {
      final n = setup.seatName(game.winner!);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final c = game.current;
    if (setup.isBot(c)) return '${_name(c)} überlegt …';
    final n = setup.seatName(c);
    if (!setup.humanControls(c)) return '${_name(c)} ist dran';
    final who = n == 'Du' ? 'Du bist dran' : '${_name(c)} ist dran';
    return _selected == null ? '$who – Figur wählen' : '$who – Ziel wählen';
  }

  /// The arm shown at the bottom: your own (offline: the first player's).
  int get _bottomArm =>
      game.homes[setup.online && !setup.spectator ? setup.mySeat : 0];

  @override
  Widget build(BuildContext context) {
    final color = halmaColors[game.homes[game.winner ?? game.current]];
    return OnlineGameFrame(
      setup: setup,
      title: 'Sternhalma',
      actions: [
        if (saveKey != null)
          RestartButton(onRestart: () => _reset(send: false, swap: false)),
      ],
      child: Column(
        children: [
          TurnBanner(
            text: _status(),
            highlight: game.isOver || setup.humanControls(game.current),
            color: color.withValues(alpha: 0.35),
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
                    avatar: CircleAvatar(
                      backgroundColor: halmaColors[game.homes[p]],
                    ),
                    label: Text(
                      '${setup.seatName(p)}: ${game.piecesHome(p)}/10',
                    ),
                    side: p == game.current && !game.isOver
                        ? BorderSide(
                            color: halmaColors[game.homes[p]],
                            width: 2,
                          )
                        : null,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AspectRatio(
                  aspectRatio: _HalmaLayout.aspect,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final layout = _HalmaLayout(box.biggest, _bottomArm);
                      return GestureDetector(
                        key: const ValueKey('halmaBoard'),
                        onTapUp: (d) {
                          final c = layout.cellAt(d.localPosition);
                          if (c != null) _tap(c);
                        },
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_hop, _rainbow]),
                          builder: (context, _) => CustomPaint(
                            size: box.biggest,
                            painter: _HalmaPainter(
                              game: game,
                              layout: layout,
                              selected: _selected,
                              targets: _targets.keys.toSet(),
                              path: _path,
                              pathPlayer: _pathPlayer,
                              hop: _hop.isAnimating ? _hop.value : null,
                              rainbow: Secrets.on(Secret.halmaRainbow)
                                  ? _rainbow.value
                                  : null,
                              ink: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (game.isOver)
            GameOverActions(
              setup: setup,
              winnerSeats: [game.winner!],
              onRematch: _reset,
            ),
        ],
      ),
    );
  }
}

/// Screen positions of the holes, turned so [bottomArm] points down.
class _HalmaLayout {
  _HalmaLayout(Size size, int bottomArm) {
    // Unit positions: arm k points at −30° − k·60° on screen. Turn so the
    // bottom arm points straight down (90°).
    final turn = (120 + bottomArm * 60) * pi / 180;
    final raw = [
      for (final (x, _, z) in HalmaBoard.cells)
        _rotate(Offset(sqrt(3) * (x + z / 2), 1.5 * z), turn),
    ];
    // The tips are 12 units from the centre; same scale for every turn.
    const radius = 12.9;
    scale = min(size.width, size.height) / (2 * radius);
    final centre = size.center(Offset.zero);
    points = [for (final p in raw) centre + p * scale];
  }

  static const aspect = 1.0;

  late final double scale;
  late final List<Offset> points;

  double get holeRadius => scale * 0.62;

  static Offset _rotate(Offset p, double a) =>
      Offset(p.dx * cos(a) - p.dy * sin(a), p.dx * sin(a) + p.dy * cos(a));

  int? cellAt(Offset p) {
    int? best;
    var bestD = scale * 0.9;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

class _HalmaPainter extends CustomPainter {
  _HalmaPainter({
    required this.game,
    required this.layout,
    required this.selected,
    required this.targets,
    required this.path,
    required this.pathPlayer,
    required this.hop,
    required this.rainbow,
    required this.ink,
  });
  final HalmaGame game;
  final _HalmaLayout layout;
  final int? selected;
  final Set<int> targets;
  final List<int>? path;
  final int? pathPlayer;
  final double? hop;
  final double? rainbow;
  final Color ink;

  Color _pieceColor(int player, int cell) {
    final base = halmaColors[game.homes[player]];
    final r = rainbow;
    if (r == null) return base;
    final hsv = HSVColor.fromColor(base);
    return hsv
        .withHue((hsv.hue + r * 360 + cell * 9) % 360)
        .withSaturation(0.85)
        .withValue(0.95)
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = layout.points;
    final hole = layout.holeRadius;
    // Star background with the arms in their colours.
    for (var c = 0; c < pts.length; c++) {
      final arm = HalmaBoard.armOf(c);
      canvas.drawCircle(
        pts[c],
        hole * 1.35,
        Paint()
          ..color = arm < 0
              ? ink.withValues(alpha: 0.06)
              : halmaColors[arm].withValues(alpha: 0.18),
      );
    }
    // Last move: a line along the hops (a rainbow with the secret on).
    final p = path;
    if (p != null && p.length > 1) {
      final line = Path()..moveTo(pts[p.first].dx, pts[p.first].dy);
      for (final c in p.skip(1)) {
        line.lineTo(pts[c].dx, pts[c].dy);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hole * 0.35
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (rainbow != null) {
        paint.shader = SweepGradient(
          colors: const [
            Colors.red,
            Colors.orange,
            Colors.yellow,
            Colors.green,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
          transform: GradientRotation(rainbow! * 2 * pi),
        ).createShader(Offset.zero & size);
      } else {
        paint.color = Colors.amber.withValues(alpha: 0.6);
      }
      canvas.drawPath(line, paint);
    }
    final moving = hop != null && p != null ? p.last : null;
    for (var c = 0; c < pts.length; c++) {
      final o = game.owner[c];
      final empty = o < 0 || c == moving;
      canvas.drawCircle(
        pts[c],
        hole * 0.45,
        Paint()..color = ink.withValues(alpha: 0.25),
      );
      if (targets.contains(c)) {
        canvas.drawCircle(
          pts[c],
          hole * 0.75,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.amber,
        );
      }
      if (!empty) _piece(canvas, pts[c], _pieceColor(o, c), c == selected);
    }
    if (moving != null) {
      // Position along the hops.
      final hops = p!.length - 1;
      final t = hop! * hops;
      final i = min(t.floor(), hops - 1);
      final f = t - i;
      final a = pts[p[i]], b = pts[p[i + 1]];
      final lift = sin(f * pi) * hole * (p.length > 2 ? 0.8 : 0.2);
      final pos = Offset.lerp(a, b, f)! - Offset(0, lift);
      _piece(canvas, pos, _pieceColor(pathPlayer!, moving), false);
    }
  }

  void _piece(Canvas canvas, Offset c, Color color, bool selected) {
    final r = layout.holeRadius;
    canvas.drawCircle(
      c + Offset(r * 0.08, r * 0.12),
      r,
      Paint()..color = Colors.black26,
    );
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1
        ..color = selected ? Colors.white : Colors.black54,
    );
    canvas.drawCircle(
      c - Offset(r * 0.3, r * 0.3),
      r * 0.25,
      Paint()..color = Colors.white60,
    );
  }

  @override
  bool shouldRepaint(_HalmaPainter old) => true;
}
