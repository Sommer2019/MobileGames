import 'dart:math';

import 'package:flutter/material.dart';

import 'billiard_logic.dart';

const _ballColors = {
  1: Color(0xFFFDD835),
  2: Color(0xFF1E88E5),
  3: Color(0xFFE53935),
  4: Color(0xFF8E24AA),
  5: Color(0xFFFB8C00),
  6: Color(0xFF43A047),
  7: Color(0xFF6D4C41),
  8: Color(0xFF212121),
};

Color ballColor(int n) =>
    n == 0 ? Colors.white : _ballColors[n > 8 ? n - 8 : n]!;

const double _rail = 0.06;

/// The table with touch aiming: touching anywhere points the cue at that
/// spot. While the cue ball is "in hand", dragging it moves it instead.
class PoolTable extends StatelessWidget {
  const PoolTable({
    super.key,
    required this.game,
    required this.aimAngle,
    required this.power,
    required this.enabled,
    required this.onAim,
    required this.onPlaceCue,
    this.highlight,
  });

  final BilliardGame game;
  final double? aimAngle;
  final double power;
  final bool enabled;
  final ValueChanged<double> onAim;
  final void Function(double x, double y) onPlaceCue;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final scale = min(
          c.maxWidth / (BilliardGame.width + _rail * 2),
          c.maxHeight / (BilliardGame.height + _rail * 2),
        );
        Offset toTable(Offset local) =>
            Offset(local.dx / scale - _rail, local.dy / scale - _rail);
        var movingCue = false;
        void handle(Offset local, {bool start = false}) {
          if (!enabled) return;
          final t = toTable(local);
          if (start) {
            final d = (t - Offset(game.cue.x, game.cue.y)).distance;
            movingCue = game.cueInHand && d < BilliardGame.radius * 3;
          }
          if (movingCue) {
            onPlaceCue(t.dx, t.dy);
            return;
          }
          final dx = t.dx - game.cue.x, dy = t.dy - game.cue.y;
          if (dx * dx + dy * dy < 1e-6) return;
          onAim(atan2(dy, dx));
        }

        return Center(
          child: SizedBox(
            width: (BilliardGame.width + _rail * 2) * scale,
            height: (BilliardGame.height + _rail * 2) * scale,
            child: GestureDetector(
              key: const ValueKey('poolTable'),
              onPanStart: (d) => handle(d.localPosition, start: true),
              onPanUpdate: (d) => handle(d.localPosition),
              onTapDown: (d) => handle(d.localPosition, start: true),
              child: CustomPaint(
                painter: TablePainter(
                  game,
                  scale,
                  enabled ? aimAngle : null,
                  power,
                  highlight: highlight,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Power bar: pull down like a cue, release to shoot. Plus fine aiming.
class CueControls extends StatefulWidget {
  const CueControls({
    super.key,
    required this.enabled,
    required this.onPower,
    required this.onShoot,
    required this.onRotate,
  });

  final bool enabled;
  final ValueChanged<double> onPower;
  final ValueChanged<double> onShoot;

  /// Rotates the aim by the given angle (radians).
  final ValueChanged<double> onRotate;

  @override
  State<CueControls> createState() => _CueControlsState();
}

class _CueControlsState extends State<CueControls> {
  double power = 0;

  void _set(double p) {
    setState(() => power = p.clamp(0.0, 1.0));
    widget.onPower(power);
  }

  @override
  Widget build(BuildContext context) {
    const fine = 0.4 * pi / 180;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _repeatButton(Icons.rotate_left, () => widget.onRotate(-fine)),
            _repeatButton(Icons.rotate_right, () => widget.onRotate(fine)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            const height = 170.0;
            return GestureDetector(
              key: const ValueKey('powerBar'),
              onVerticalDragStart: widget.enabled ? (_) => _set(0) : null,
              onVerticalDragUpdate: widget.enabled
                  ? (d) => _set(power + d.delta.dy / height)
                  : null,
              onVerticalDragEnd: widget.enabled
                  ? (_) {
                      final p = power;
                      _set(0);
                      if (p > 0.03) widget.onShoot(p);
                    }
                  : null,
              child: Container(
                width: 64,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: height * power,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Colors.green, Colors.orange, Colors.red],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          widget.enabled ? 'ziehen ↓ & loslassen' : 'warten …',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _repeatButton(IconData icon, VoidCallback onStep) => GestureDetector(
    onTap: widget.enabled ? onStep : null,
    onLongPressStart: widget.enabled ? (_) => _repeat(onStep) : null,
    onLongPressEnd: (_) => _repeating = false,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white),
    ),
  );

  bool _repeating = false;

  Future<void> _repeat(VoidCallback step) async {
    _repeating = true;
    while (_repeating && mounted) {
      step();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

class TablePainter extends CustomPainter {
  TablePainter(
    this.game,
    this.scale,
    this.aimAngle,
    this.power, {
    this.highlight,
  });

  final BilliardGame game;
  final double scale;
  final double? aimAngle;
  final double power;

  /// Ball to mark (the one that has to be hit first).
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(_rail * scale),
      ),
      Paint()..color = const Color(0xFF5D4037),
    );
    canvas.translate(_rail * scale, _rail * scale);
    final felt = Rect.fromLTWH(
      0,
      0,
      BilliardGame.width * scale,
      BilliardGame.height * scale,
    );
    canvas.drawRect(felt, Paint()..color = const Color(0xFF1B7A3E));
    Offset p(double x, double y) => Offset(x * scale, y * scale);
    canvas.drawCircle(
      p(BilliardGame.width * 0.25, BilliardGame.height / 2),
      2,
      Paint()..color = Colors.white38,
    );
    for (final (x, y) in BilliardGame.pockets) {
      canvas.drawCircle(
        p(x, y),
        BilliardGame.pocketRadius * scale,
        Paint()..color = Colors.black,
      );
    }
    final r = BilliardGame.radius * scale;
    for (final b in game.balls) {
      if (b.pocketed) continue;
      _ball(canvas, b, p(b.x, b.y), r);
    }
    if (game.cueInHand && !game.moving) {
      canvas.drawCircle(
        p(game.cue.x, game.cue.y),
        r * 2.2,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final angle = aimAngle;
    if (angle != null && !game.moving && !game.cue.pocketed) {
      final c = p(game.cue.x, game.cue.y);
      final dir = Offset(cos(angle), sin(angle));
      final pre = game.preview(angle);
      final guide = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5;
      final ghost = p(pre.x, pre.y);
      canvas.drawLine(c + dir * r, ghost, guide);
      canvas.drawCircle(
        ghost,
        r,
        Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final hit = pre.ball;
      if (hit != null) {
        // Where the hit ball will roll.
        final from = p(hit.x, hit.y);
        canvas.drawLine(
          from,
          from + Offset(pre.dirX, pre.dirY) * scale * 0.35,
          Paint()
            ..color = Colors.yellowAccent
            ..strokeWidth = 2,
        );
      }
      // The cue stick, pulled back with the power.
      final back = r + 4 + power * scale * 0.25;
      canvas.drawLine(
        c - dir * back,
        c - dir * (back + scale * 0.9),
        Paint()
          ..color = const Color(0xFFD7B377)
          ..strokeWidth = r * 0.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _ball(Canvas canvas, Ball b, Offset c, double r) {
    if (b.number == highlight) {
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    canvas.drawCircle(
      c + const Offset(1.5, 2),
      r,
      Paint()..color = Colors.black38,
    );
    final color = ballColor(b.number);
    canvas.drawCircle(
      c,
      r,
      Paint()..color = b.number > 8 ? Colors.white : color,
    );
    if (b.number > 8) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawRect(
        Rect.fromCenter(center: c, width: r * 2, height: r * 1.1),
        Paint()..color = color,
      );
      canvas.restore();
    }
    if (b.number != 0) {
      canvas.drawCircle(c, r * 0.48, Paint()..color = Colors.white);
      final tp = TextPainter(
        text: TextSpan(
          text: '${b.number}',
          style: TextStyle(
            fontSize: r * 0.62,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(
      c - Offset(r * 0.35, r * 0.35),
      r * 0.25,
      Paint()..color = Colors.white38,
    );
  }

  @override
  bool shouldRepaint(TablePainter old) => true;
}
