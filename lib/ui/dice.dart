import 'dart:math';

import 'package:flutter/material.dart';

/// A die that tumbles whenever [rollId] changes: it jumps, spins and shows
/// random faces before it settles on [value].
class RollingDie extends StatefulWidget {
  const RollingDie({
    super.key,
    required this.value,
    required this.rollId,
    this.held = false,
    this.visible = true,
    this.duration = const Duration(milliseconds: 700),
  });

  /// 1..6
  final int value;

  /// Changes each time this die is rolled.
  final int rollId;
  final bool held;

  /// False before the first roll: an empty die.
  final bool visible;
  final Duration duration;

  @override
  State<RollingDie> createState() => _RollingDieState();
}

class _RollingDieState extends State<RollingDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  final Random _random = Random();
  double _direction = 1;

  @override
  void didUpdateWidget(RollingDie old) {
    super.didUpdateWidget(old);
    if (old.rollId != widget.rollId) {
      _direction = _random.nextBool() ? 1 : -1;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest.shortestSide;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final rolling = t < 1;
            // Random faces while tumbling, the result for the last part.
            final face = rolling && t < 0.72
                ? 1 + (widget.rollId * 7 + (t * 12).floor() * 5) % 6
                : widget.value;
            final spin =
                (1 - Curves.easeOutCubic.transform(t)) * 2.2 * pi * _direction;
            final jump = rolling ? -sin(t * pi) * size * 0.28 : 0.0;
            final squash = rolling ? 1 + 0.1 * sin(t * pi) : 1.0;
            return Transform.translate(
              offset: Offset(0, jump),
              child: Transform.rotate(
                angle: spin,
                child: Transform.scale(
                  scale: squash,
                  child: DieView(
                    value: face,
                    held: widget.held,
                    visible: widget.visible,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A single die: white rounded square with pips (amber when held).
class DieView extends StatelessWidget {
  const DieView({
    super.key,
    required this.value,
    this.held = false,
    this.visible = true,
  });
  final int value;
  final bool held;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: held ? Colors.amber.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: held ? Colors.amber.shade800 : Colors.black26,
          width: held ? 3 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      child: visible
          ? CustomPaint(painter: DiePainter(value), size: Size.infinite)
          : null,
    );
  }
}

class DiePainter extends CustomPainter {
  DiePainter(this.value);
  final int value;

  static const pips = {
    1: [(0.5, 0.5)],
    2: [(0.25, 0.25), (0.75, 0.75)],
    3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
    6: [
      (0.25, 0.22),
      (0.75, 0.22),
      (0.25, 0.5),
      (0.75, 0.5),
      (0.25, 0.78),
      (0.75, 0.78),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    for (final (x, y) in pips[value]!) {
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        size.width * 0.09,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DiePainter old) => old.value != value;
}
