import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A clearly visible frame around the element the D-pad / keyboard is on.
///
/// Material only tints a focused button a little, which is hard to see on a
/// handheld at arm's length. While the app is driven by keys (Flutter's
/// "traditional" highlight mode – a touch switches it off again), a thick,
/// gently pulsing frame follows the focus, gliding from one element to the
/// next.
class FocusHighlight extends StatefulWidget {
  const FocusHighlight({super.key, required this.child});
  final Widget child;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight>
    with SingleTickerProviderStateMixin {
  final _key = GlobalKey();
  late final Ticker _ticker = createTicker(_tick);
  Rect? _rect;
  Duration _now = Duration.zero;

  FocusManager get _fm => FocusManager.instance;

  @override
  void initState() {
    super.initState();
    _fm.addListener(_changed);
    _fm.addHighlightModeListener(_mode);
    _changed();
  }

  @override
  void dispose() {
    _fm.removeListener(_changed);
    _fm.removeHighlightModeListener(_mode);
    _ticker.dispose();
    super.dispose();
  }

  bool get _keys => _fm.highlightMode == FocusHighlightMode.traditional;

  void _mode(FocusHighlightMode _) => _changed();

  void _changed() {
    final on = _keys && _fm.primaryFocus != null;
    if (on && !_ticker.isActive) _ticker.start();
    if (!on) {
      _ticker.stop();
      if (_rect != null && mounted) setState(() => _rect = null);
    }
  }

  /// The frame follows scrolling and animations, so it is measured every
  /// frame while keys are in use.
  void _tick(Duration now) {
    _now = now;
    final r = _target();
    if (r != _rect || r != null) setState(() => _rect = r);
  }

  Rect? _target() {
    final node = _fm.primaryFocus;
    if (node == null || node is FocusScopeNode || node.context == null) {
      return null;
    }
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final Rect r;
    try {
      r = node.rect;
    } catch (_) {
      return null;
    }
    final origin = box.localToGlobal(Offset.zero);
    final local = r.shift(-origin);
    final screen = Offset.zero & box.size;
    // Whole game areas (Snake, Sudoku, Labyrinth listen to keys) are not
    // buttons: no frame around the full screen.
    if (local.width * local.height > screen.width * screen.height * 0.45) {
      return null;
    }
    if (!local.overlaps(screen) || local.isEmpty) return null;
    return local;
  }

  @override
  Widget build(BuildContext context) {
    final r = _rect;
    final scheme = Theme.of(context).colorScheme;
    final pulse = 0.5 + 0.5 * sin(_now.inMilliseconds / 1000 * 2 * pi / 1.2);
    return Stack(
      key: _key,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (r != null)
          AnimatedPositioned(
            key: const ValueKey('focusHighlight'),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            left: r.left - 4,
            top: r.top - 4,
            width: r.width + 8,
            height: r.height + 8,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FramePainter(
                  pulse: pulse,
                  radius: min(18, min(r.width, r.height) / 2 + 4),
                  outline: scheme.shadow,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A thick amber frame with a soft glow around it – only on the border, the
/// element itself stays as it is.
class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.pulse,
    required this.radius,
    required this.outline,
  });

  final double pulse;
  final double radius;
  final Color outline;

  static const _amber = Color(0xFFFFC107);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1.5),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 + 4 * pulse
        ..color = _amber.withValues(alpha: 0.25 + 0.3 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 3 * pulse),
    );
    // Dark edge outside, so the frame shows on yellow and white, too.
    canvas.drawRRect(
      r.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = outline.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _amber,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.pulse != pulse || old.radius != radius || old.outline != outline;
}
