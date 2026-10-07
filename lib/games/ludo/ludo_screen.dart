import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/net/room.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/shake.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/dice.dart';
import '../../ui/play_setup.dart';
import 'ludo_logic.dart';

const ludoColors = [
  Color(0xFFE53935), // Rot
  Color(0xFF1E88E5), // Blau
  Color(0xFF43A047), // Grün
  Color(0xFFFDD835), // Gelb
];
const ludoColorNames = ['Rot', 'Blau', 'Grün', 'Gelb'];

/// Grid cells (column, row) of the 11 × 11 board.
class LudoBoard {
  /// The 40 track fields, starting at the start field of side 0.
  static final List<(int, int)> track = () {
    final t = <(int, int)>[];
    for (var x = 0; x <= 4; x++) {
      t.add((x, 4));
    }
    for (var y = 3; y >= 0; y--) {
      t.add((4, y));
    }
    t
      ..add((5, 0))
      ..add((6, 0));
    for (var y = 1; y <= 4; y++) {
      t.add((6, y));
    }
    for (var x = 7; x <= 10; x++) {
      t.add((x, 4));
    }
    t
      ..add((10, 5))
      ..add((10, 6));
    for (var x = 9; x >= 6; x--) {
      t.add((x, 6));
    }
    for (var y = 7; y <= 10; y++) {
      t.add((6, y));
    }
    t
      ..add((5, 10))
      ..add((4, 10));
    for (var y = 9; y >= 6; y--) {
      t.add((4, y));
    }
    for (var x = 3; x >= 0; x--) {
      t.add((x, 6));
    }
    t.add((0, 5));
    return t;
  }();

  /// Goal fields of each side (first to last).
  static (int, int) goal(int side, int i) => switch (side) {
    0 => (1 + i, 5),
    1 => (5, 1 + i),
    2 => (9 - i, 5),
    _ => (5, 9 - i),
  };

  /// House fields of each side.
  static (int, int) house(int side, int i) {
    const corners = [(0, 0), (9, 0), (9, 9), (0, 9)];
    final (cx, cy) = corners[side];
    return (cx + i % 2, cy + i ~/ 2);
  }
}

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with SavedGameState, BotTurns, TickerProviderStateMixin {
  late int round = widget.setup.firstRound;
  late LudoGame game = LudoGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  bool _rolling = false;
  int _shownDie = 1;
  StreamSubscription<Object>? _shakeSub;

  /// Flying pieces (secret), by (player, piece).
  final Map<(int, int), _Flyer> _flyers = {};
  late final Ticker _flyTicker = createTicker(_fly);
  Duration _lastFly = Duration.zero;
  Offset? _panStart;

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  @override
  String? get saveKey => setup.saveKey('ludo');

  @override
  Map<String, dynamic>? saveGame() {
    if (game.isOver || game.events.isEmpty) return null;
    return {'round': round, 'events': game.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = LudoGame.replay(players, data['events'] as List, first: round);
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    _shakeSub = ShakeDetector.listen(_onShake);
    scheduleBot();
  }

  /// Shaking rolls the die; with the secret on it also throws all pieces
  /// into the air when it is not your roll.
  void _onShake() {
    if (!mounted) return;
    if (_myRoll) {
      HapticFeedback.mediumImpact();
      _roll(game.current);
    } else if (Secrets.on(Secret.ludoFling)) {
      HapticFeedback.heavyImpact();
      _whirl();
    }
  }

  /// Throws every piece into the air.
  void _whirl() {
    for (var p = 0; p < players; p++) {
      for (var i = 0; i < 4; i++) {
        final a = _random.nextDouble() * 2 * pi;
        final speed = 8 + _random.nextDouble() * 10;
        _launch(p, i, Offset(cos(a), sin(a)) * speed);
      }
    }
  }

  Offset _cellCenter(int p, int i) {
    final (x, y) = _cellOf(p, i, game.sideOf(p));
    return Offset(x + 0.5, y + 0.5);
  }

  /// Flicks piece [i] of player [p] with [velocity] (cells per second).
  void _launch(int p, int i, Offset velocity) {
    _flyers[(p, i)] = _Flyer.free(
      _flyers[(p, i)]?.pos ?? _cellCenter(p, i),
      velocity,
      spin: (_random.nextDouble() - 0.5) * 20,
    );
    if (!_flyTicker.isActive) {
      _lastFly = Duration.zero;
      _flyTicker.start();
    }
  }

  void _fly(Duration now) {
    final dt = _lastFly == Duration.zero
        ? 1 / 60
        : (now - _lastFly).inMicroseconds / 1e6;
    _lastFly = now;
    _flyers.removeWhere((key, f) {
      f.step(min(dt, 0.05), _cellCenter(key.$1, key.$2));
      return f.done;
    });
    if (_flyers.isEmpty) _flyTicker.stop();
    setState(() {});
  }

  void _panStarted(DragStartDetails d) => _panStart = d.localPosition;

  void _panEnded(DragEndDetails d, double cell) {
    final start = _panStart;
    _panStart = null;
    if (start == null || !Secrets.on(Secret.ludoFling)) return;
    final at = start / cell;
    for (var p = 0; p < players; p++) {
      for (var i = 0; i < 4; i++) {
        final c = _flyers[(p, i)]?.pos ?? _cellCenter(p, i);
        if ((c - at).distance < 0.6) {
          final v = d.velocity.pixelsPerSecond / cell;
          if (v.distance < 2) return;
          Sound.play(Sfx.click);
          _launch(p, i, v * 0.9);
          return;
        }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _shakeSub?.cancel();
    _flyTicker.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  int? get seatToMove => game.isOver || _rolling ? null : game.current;

  @override
  void botAct(int seat) {
    if (game.mustRoll) {
      _roll(seat);
    } else {
      _move(LudoAi(_random).choose(game), seat);
    }
  }

  void _onMessage(RoomMessage m) {
    final d = m.data;
    switch (d['t']) {
      case 'roll':
        if (m.seat != game.current) return;
        final v = d['v'];
        if (v is int) _applyRoll(v);
      case 'move':
        if (m.seat != game.current) return;
        final p = d['p'];
        if (p is int) _applyMove(p);
      case 'rematch':
        _reset(send: false);
    }
  }

  Future<void> _roll(int seat) async {
    if (!game.mustRoll || _rolling) return;
    final v = _random.nextInt(6) + 1;
    setup.sendAs(seat, {'t': 'roll', 'v': v});
    await _applyRoll(v);
  }

  /// Shows the die tumbling, then applies the roll.
  Future<void> _applyRoll(int v) async {
    setState(() => _rolling = true);
    Sound.play(Sfx.dice);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      setState(() => _shownDie = _random.nextInt(6) + 1);
    }
    setState(() {
      _shownDie = v;
      _rolling = false;
      game.roll(v);
    });
    persistGame();
    scheduleBot();
  }

  void _move(int piece, int seat) {
    if (!game.movable().contains(piece)) return;
    setup.sendAs(seat, {'t': 'move', 'p': piece});
    _applyMove(piece);
  }

  void _applyMove(int piece) {
    final mover = game.current;
    setState(() => game.move(piece));
    final cap = game.lastCapture;
    if (cap != null && Secrets.on(Secret.ludoFling)) {
      // The captured piece flies home in a high arc from where it was hit.
      _flyers[cap] = _Flyer.arc(
        _cellCenter(mover, piece),
        _cellCenter(cap.$1, cap.$2),
      );
      if (!_flyTicker.isActive) {
        _lastFly = Duration.zero;
        _flyTicker.start();
      }
    }
    if (game.lastCapture != null) {
      Sound.play(Sfx.thud);
      if (Secrets.on(Secret.ludoRage)) _shake.forward(from: 0);
    } else {
      Sound.play(Sfx.place);
    }
    persistGame();
    scheduleBot();
  }

  bool get _myRoll =>
      game.mustRoll && !_rolling && setup.humanControls(game.current);

  void _tapCell(int col, int row) {
    if (game.mustRoll || _rolling || !setup.humanControls(game.current)) {
      return;
    }
    final side = game.sideOf(game.current);
    for (final i in game.movable()) {
      if (_cellOf(game.current, i, side) == (col, row)) {
        _move(i, game.current);
        return;
      }
    }
  }

  (int, int) _cellOf(int player, int piece, int side) {
    final pos = game.pieces[player][piece];
    if (pos < 0) return LudoBoard.house(side, piece);
    if (pos >= LudoGame.goalStart) {
      return LudoBoard.goal(side, pos - LudoGame.goalStart);
    }
    return LudoBoard.track[game.absolute(player, pos)];
  }

  void _reset({bool send = true, bool swap = true}) {
    setState(() {
      if (swap) round++;
      game = LudoGame(players: players, first: round);
    });
    if (send) setup.send({'t': 'rematch'});
    persistGame();
    scheduleBot();
  }

  String _name(int p) =>
      '${setup.seatName(p)} (${ludoColorNames[game.sideOf(p)]})';

  String _status() {
    if (game.isOver) {
      final n = setup.seatName(game.winner!);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final n = _name(game.current);
    final me = setup.seatName(game.current) == 'Du';
    if (setup.isBot(game.current)) return '$n ist dran …';
    if (game.mustRoll) {
      final tries = game.triesLeft > 1 ? ' (${game.triesLeft} Versuche)' : '';
      return me ? 'Du bist dran – würfeln$tries' : '$n würfelt$tries';
    }
    return me ? 'Du hast eine ${game.die} – Figur wählen' : '$n zieht';
  }

  @override
  Widget build(BuildContext context) {
    final color =
        ludoColors[game.sideOf(game.isOver ? game.winner! : game.current)];
    return OnlineGameFrame(
      setup: setup,
      title: 'Ludo',
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
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = sin(t * pi * 10) * 12 * (1 - t);
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (context, box) => GestureDetector(
                        key: const ValueKey('ludoBoard'),
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: _panStarted,
                        onPanEnd: (d) => _panEnded(d, box.maxWidth / 11),
                        onTapUp: (d) {
                          final cell = box.maxWidth / 11;
                          _tapCell(
                            (d.localPosition.dx / cell).floor(),
                            (d.localPosition.dy / cell).floor(),
                          );
                        },
                        child: CustomPaint(
                          size: box.biggest,
                          painter: _LudoPainter(this),
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
              winnerSeats: [game.winner!],
              onRematch: _reset,
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                key: const ValueKey('ludoDie'),
                onTap: _myRoll ? () => _roll(game.current) : null,
                child: Opacity(
                  opacity: _myRoll || _rolling || !game.mustRoll ? 1 : 0.5,
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DieView(value: _shownDie),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LudoPainter extends CustomPainter {
  _LudoPainter(this.s);
  final _LudoScreenState s;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 11;
    final g = s.game;
    Offset center((int, int) c) =>
        Offset((c.$1 + 0.5) * cell, (c.$2 + 0.5) * cell);
    final bg = Paint()..color = const Color(0xFFFFF3D6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      bg,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black54;
    void field((int, int) c, Color fill) {
      canvas.drawCircle(center(c), cell * 0.4, Paint()..color = fill);
      canvas.drawCircle(center(c), cell * 0.4, ring);
    }

    // Track (start fields in the side colour).
    for (var i = 0; i < 40; i++) {
      final side = i % 10 == 0 ? i ~/ 10 : -1;
      field(
        LudoBoard.track[i],
        side >= 0 ? ludoColors[side].withValues(alpha: 0.7) : Colors.white,
      );
    }
    for (var side = 0; side < 4; side++) {
      final faded = ludoColors[side].withValues(alpha: 0.25);
      for (var i = 0; i < 4; i++) {
        field(LudoBoard.goal(side, i), faded);
        field(LudoBoard.house(side, i), faded);
      }
    }
    // Movable pieces glow.
    final movable = s.setup.humanControls(g.current) ? g.movable() : const [];
    for (var p = 0; p < g.players; p++) {
      final side = g.sideOf(p);
      for (var i = 0; i < 4; i++) {
        if (s._flyers.containsKey((p, i))) continue;
        final c = center(s._cellOf(p, i, side));
        if (p == g.current && movable.contains(i)) {
          canvas.drawCircle(
            c,
            cell * 0.48,
            Paint()..color = Colors.black.withValues(alpha: 0.35),
          );
        }
        final color = ludoColors[side];
        canvas.drawCircle(
          c + Offset(cell * 0.03, cell * 0.05),
          cell * 0.3,
          Paint()..color = Colors.black26,
        );
        canvas.drawCircle(c, cell * 0.3, Paint()..color = color);
        canvas.drawCircle(
          c,
          cell * 0.3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.black87,
        );
        canvas.drawCircle(
          c - Offset(cell * 0.09, cell * 0.09),
          cell * 0.08,
          Paint()..color = Colors.white70,
        );
      }
    }
    // Flying pieces (secret): above everything, bigger when higher.
    s._flyers.forEach((key, f) {
      final c = f.pos * cell;
      final r = cell * 0.3 * (1 + f.height * 0.6);
      canvas.drawCircle(
        c + Offset(cell * 0.15, cell * 0.25) * (1 + f.height * 2),
        cell * 0.3,
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(f.angle);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()..color = ludoColors[g.sideOf(key.$1)],
      );
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black87,
      );
      canvas.drawCircle(
        Offset(-r * 0.3, -r * 0.3),
        r * 0.27,
        Paint()..color = Colors.white70,
      );
      canvas.restore();
    });
  }

  @override
  bool shouldRepaint(_LudoPainter old) => true;
}

/// A piece flying around (secret „Flugfiguren“), in cell units.
class _Flyer {
  _Flyer.free(this.pos, this.vel, {this.spin = 0}) : _arc = null;

  _Flyer.arc(Offset from, Offset to)
    : pos = from,
      vel = Offset.zero,
      spin = 9,
      _arc = (from, to);

  Offset pos;
  Offset vel;
  double spin;
  double angle = 0;
  double age = 0;
  double height = 0;
  bool done = false;
  final (Offset, Offset)? _arc;

  static const _freeTime = 1.8, _returnTime = 0.45, _arcTime = 0.9;

  /// Moves on by [dt] seconds; [home] is where the piece belongs.
  void step(double dt, Offset home) {
    age += dt;
    angle += spin * dt;
    final arc = _arc;
    if (arc != null) {
      final t = (age / _arcTime).clamp(0.0, 1.0);
      pos = Offset.lerp(arc.$1, home, Curves.easeInOut.transform(t))!;
      height = sin(t * pi) * 1.4;
      done = t >= 1;
      return;
    }
    if (age < _freeTime) {
      // Slides over the board, bounces off the edges, slows down.
      pos += vel * dt;
      if (pos.dx < 0.3 || pos.dx > 10.7) {
        vel = Offset(-vel.dx * 0.85, vel.dy);
        pos = Offset(pos.dx.clamp(0.3, 10.7), pos.dy);
      }
      if (pos.dy < 0.3 || pos.dy > 10.7) {
        vel = Offset(vel.dx, -vel.dy * 0.85);
        pos = Offset(pos.dx, pos.dy.clamp(0.3, 10.7));
      }
      vel *= pow(0.35, dt).toDouble();
      spin *= pow(0.5, dt).toDouble();
      height = (sin(age * 7).abs() * 0.5) * (1 - age / _freeTime);
      return;
    }
    // Glides back home.
    final t = ((age - _freeTime) / _returnTime).clamp(0.0, 1.0);
    pos = Offset.lerp(pos, home, t)!;
    height = sin(t * pi) * 0.3;
    done = t >= 1;
  }
}
