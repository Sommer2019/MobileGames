import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Colourful paper rain over the whole area; disappears on its own.
class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.onDone, this.pieces = 140});
  final VoidCallback onDone;
  final int pieces;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Piece {
  _Piece(Random r)
    : x = r.nextDouble(),
      y = -r.nextDouble() * 0.6,
      vx = (r.nextDouble() - 0.5) * 0.15,
      vy = 0.25 + r.nextDouble() * 0.35,
      spin = (r.nextDouble() - 0.5) * 12,
      angle = r.nextDouble() * pi,
      color = Colors.primaries[r.nextInt(Colors.primaries.length)];
  double x, y, vx, vy, angle;
  final double spin;
  final Color color;
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final Random _r = Random();
  late final List<_Piece> _pieces = [
    for (var i = 0; i < widget.pieces; i++) _Piece(_r),
  ];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : min((now - _last).inMicroseconds / 1e6, 0.05);
    _last = now;
    for (final p in _pieces) {
      p.x += (p.vx + sin(p.angle) * 0.05) * dt;
      p.y += p.vy * dt;
      p.angle += p.spin * dt;
    }
    if (_pieces.every((p) => p.y > 1.1) || now > const Duration(seconds: 6)) {
      _ticker.stop();
      widget.onDone();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces)),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces);
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      canvas.save();
      canvas.translate(p.x * size.width, p.y * size.height);
      canvas.rotate(p.angle);
      // Turning paper: the width changes with the angle.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: 10 * cos(p.angle * 1.7).abs() + 2,
          height: 6,
        ),
        Paint()..color = p.color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}
