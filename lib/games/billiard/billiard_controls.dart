import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../core/sphere.dart';
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

/// Plays the clicks, cushion knocks and pocket sounds collected by [game]
/// since the last call.
void playTableSounds(BilliardGame game) {
  final (ball, cushion, pockets) = game.takeSounds();
  if (ball > 0.05) Sound.play(Sfx.clack, volume: min(1, ball / 2.5 + 0.15));
  if (cushion > 0.2) {
    Sound.play(Sfx.thud, volume: min(0.7, cushion / 4), minGap: Duration.zero);
  }
  if (pockets > 0) Sound.play(Sfx.pocket);
}

/// Rail width; wide enough to hold the pockets completely.
const double _rail = 0.08;

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
    this.spin = Offset.zero,
  });

  /// Where the cue hits the cue ball (see [SpinPicker]).
  final Offset spin;

  final BilliardGame game;
  final double? aimAngle;
  final double power;
  final bool enabled;
  final ValueChanged<double> onAim;
  final void Function(double x, double y) onPlaceCue;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(6), child: _table());
  }

  Widget _table() {
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
              child: ListenableBuilder(
                listenable: Secrets.I,
                builder: (context, _) {
                  final table = TablePainter(
                    game,
                    scale,
                    enabled ? aimAngle : null,
                    power,
                    highlight: highlight,
                    spin: spin,
                    disco: Secrets.on(Secret.disco),
                  );
                  return CustomPaint(
                    painter: Secrets.on(Secret.retro)
                        ? PixelatedPainter(table, pixel: 3.5)
                        : table,
                  );
                },
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
    this.spin,
    this.onSpin,
  });

  /// Hit point on the cue ball; the picker is shown when [onSpin] is set.
  final Offset? spin;
  final ValueChanged<Offset>? onSpin;

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _repeatButton(Icons.rotate_left, (f) => widget.onRotate(-f)),
            _repeatButton(Icons.rotate_right, (f) => widget.onRotate(f)),
          ],
        ),
        if (widget.onSpin != null) ...[
          const SizedBox(height: 8),
          SpinPicker(
            spin: widget.spin ?? Offset.zero,
            enabled: widget.enabled,
            onChanged: widget.onSpin!,
          ),
        ],
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            const height = 150.0;
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

  /// One tap turns the cue by a tenth of a degree; holding the button
  /// starts just as finely and then gets faster.
  static const _fineStep = 0.1 * pi / 180;

  Widget _repeatButton(IconData icon, ValueChanged<double> onStep) =>
      GestureDetector(
        onTap: widget.enabled ? () => onStep(_fineStep) : null,
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

  Future<void> _repeat(ValueChanged<double> step) async {
    _repeating = true;
    var n = 0;
    while (_repeating && mounted) {
      // 0.1° steps for the first second, up to 1° when held longer.
      step(_fineStep * min(10, 1 + max(0, n - 25) / 5));
      n++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// The cue ball seen from the player: tap where the cue should hit it.
/// Above the centre = follow, below = draw, left/right = side spin.
/// Double tap resets to the centre. The value is in -1..1 with y up.
class SpinPicker extends StatelessWidget {
  const SpinPicker({
    super.key,
    required this.spin,
    required this.onChanged,
    this.enabled = true,
    this.size = 64,
  });

  final Offset spin;
  final ValueChanged<Offset> onChanged;
  final bool enabled;
  final double size;

  /// Hits further out than this would miscue.
  static const double maxOffset = 0.75;

  void _set(Offset local) {
    final r = size / 2;
    var v = Offset((local.dx - r) / r, -(local.dy - r) / r);
    if (v.distance > maxOffset) v = v / v.distance * maxOffset;
    // Snap to the centre near the middle.
    if (v.distance < 0.08) v = Offset.zero;
    onChanged(v);
  }

  String get label {
    if (spin == Offset.zero) return 'Mitte';
    final parts = <String>[
      if (spin.dy > 0.15) 'Nachläufer',
      if (spin.dy < -0.15) 'Rückläufer',
      if (spin.dx > 0.15) 'rechts',
      if (spin.dx < -0.15) 'links',
    ];
    return parts.isEmpty ? 'Mitte' : parts.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey('spinPicker'),
          onTapDown: enabled ? (d) => _set(d.localPosition) : null,
          onPanUpdate: enabled ? (d) => _set(d.localPosition) : null,
          onDoubleTap: enabled ? () => onChanged(Offset.zero) : null,
          child: CustomPaint(
            size: Size.square(size),
            painter: _SpinPainter(spin),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: size + 24,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
      ],
    );
  }
}

class _SpinPainter extends CustomPainter {
  _SpinPainter(this.spin);
  final Offset spin;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r * SpinPicker.maxOffset,
      Paint()
        ..color = Colors.black12
        ..style = PaintingStyle.stroke,
    );
    final cross = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    canvas.drawLine(c - Offset(r * 0.8, 0), c + Offset(r * 0.8, 0), cross);
    canvas.drawLine(c - Offset(0, r * 0.8), c + Offset(0, r * 0.8), cross);
    canvas.drawCircle(
      c + Offset(spin.dx * r, -spin.dy * r),
      r * 0.16,
      Paint()..color = Colors.redAccent,
    );
  }

  @override
  bool shouldRepaint(_SpinPainter old) => old.spin != spin;
}

/// Draws [inner] in coarse pixels, like an old video game.
class PixelatedPainter extends CustomPainter {
  PixelatedPainter(this.inner, {this.pixel = 4});
  final CustomPainter inner;

  /// Size of one "pixel" in logical pixels.
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final w = max(1, (size.width / pixel).ceil());
    final h = max(1, (size.height / pixel).ceil());
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..scale(1 / pixel);
    inner.paint(c, size);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, w * pixel, h * pixel),
      Paint()..filterQuality = FilterQuality.none,
    );
    image.dispose();
  }

  @override
  bool shouldRepaint(PixelatedPainter old) => true;
}

class TablePainter extends CustomPainter {
  TablePainter(
    this.game,
    this.scale,
    this.aimAngle,
    this.power, {
    this.highlight,
    this.spin = Offset.zero,
    this.disco = false,
  });

  /// Hit point on the cue ball, for the predicted cue ball path.
  final Offset spin;

  /// Secret: balls change colour as they roll.
  final bool disco;

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
      final pre = game.preview(angle, spinY: spin.dy);
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
        // Where the cue ball goes after the contact.
        final cuePath = Offset(pre.cueX, pre.cueY);
        if (cuePath.distance > 0.02) {
          canvas.drawLine(
            ghost,
            ghost + cuePath * scale * 0.35,
            Paint()
              ..color = Colors.white38
              ..strokeWidth = 1.5,
          );
        }
      }
      // The cue stick, pulled back with the power.
      final back = r + 4 + power * scale * 0.25;
      canvas.drawLine(
        c - dir * back,
        c - dir * (back + scale * 0.45),
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
    final o = b.orientation;
    var color = ballColor(b.number);
    if (disco && b.number != 0) {
      final hue =
          (atan2(o.qy, o.qx) * 180 / pi + o.qz * 120 + b.number * 24) % 360;
      color = HSVColor.fromAHSV(1, (hue + 360) % 360, 0.85, 0.95).toColor();
    }
    final white = Paint()..color = Colors.white;
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    if (b.number > 8) {
      // Stripe: white caps around both ends of the stripe axis.
      for (final sign in const [1.0, -1.0]) {
        final cap = SphereOrientation.capPath(
          c,
          r,
          o.ax * sign,
          o.ay * sign,
          o.az * sign,
          0.98,
        );
        if (cap != null) canvas.drawPath(cap, white);
      }
    }
    if (b.number == 0) {
      // A few red dots make the cue ball's rotation visible.
      final dot = Paint()..color = const Color(0xFFE53935);
      for (final (x, y, z) in [
        (o.qx, o.qy, o.qz),
        (-o.qx, -o.qy, -o.qz),
        (o.ax, o.ay, o.az),
        (-o.ax, -o.ay, -o.az),
      ]) {
        final spot = SphereOrientation.capPath(c, r, x, y, z, 0.16);
        if (spot != null) canvas.drawPath(spot, dot);
      }
    } else {
      // Number circles on two opposite sides.
      for (final sign in const [1.0, -1.0]) {
        final qx = o.qx * sign, qy = o.qy * sign, qz = o.qz * sign;
        final spot = SphereOrientation.capPath(c, r, qx, qy, qz, 0.5);
        if (spot == null) continue;
        canvas.drawPath(spot, white);
        if (qz > 0.3) _number(canvas, b.number, c, r, qx, qy, qz);
      }
    }
    canvas.restore();
    // Fixed reflection of the light.
    canvas.drawCircle(
      c - Offset(r * 0.35, r * 0.35),
      r * 0.25,
      Paint()..color = Colors.white38,
    );
  }

  /// The number, squeezed towards the edge like on a real ball.
  void _number(
    Canvas canvas,
    int number,
    Offset c,
    double r,
    double qx,
    double qy,
    double qz,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          fontSize: r * 0.62,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dir = atan2(qy, qx);
    canvas.save();
    canvas.translate(c.dx + qx * r, c.dy + qy * r);
    canvas.rotate(dir);
    canvas.scale(qz, 1);
    canvas.rotate(-dir);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(TablePainter old) => true;
}
