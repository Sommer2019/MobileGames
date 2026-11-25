import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/gamepad.dart';

/// Makes the whole app usable with gamepads and handhelds such as the
/// AYN Thor:
///
/// * B goes back (closes dialogs, leaves games – with the usual question).
/// * D-pad / left stick move the focus between buttons, A presses them
///   (built into Flutter); in Snake they steer.
/// * The right stick shows a pointer. A (or R1) taps where it points; held
///   down it drags, e.g. cards in Solitaire or the cue in billiards. So every
///   board can be played without touching the screen.
class GamepadCursor extends StatefulWidget {
  const GamepadCursor({
    super.key,
    required this.child,
    required this.onBack,
    this.sticks,
  });

  final Widget child;

  /// Called for the B button.
  final VoidCallback onBack;

  /// Stick positions; by default from [Gamepad].
  final Stream<StickState>? sticks;

  @override
  State<GamepadCursor> createState() => _GamepadCursorState();
}

class _GamepadCursorState extends State<GamepadCursor>
    with SingleTickerProviderStateMixin {
  /// Full deflection crosses the screen width in about this many seconds.
  static const _crossTime = 1.1;

  /// The pointer hides after this long without use.
  static const _idle = Duration(seconds: 6);

  static const _device = 0x7A7;
  static int _nextPointer = 0x7A70000;

  final _key = GlobalKey();
  late final Ticker _ticker = createTicker(_tick);
  StreamSubscription<StickState>? _sub;
  Offset _stick = Offset.zero;
  Offset? _pos;
  bool _visible = false;
  Duration? _lastTick;
  Timer? _hide;

  /// The pointer of the synthesized touch while A is held.
  int? _pointer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _sub = (widget.sticks ?? Gamepad.I.sticks).listen(_onSticks);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sub?.cancel();
    _hide?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  Size get _size =>
      (_key.currentContext?.findRenderObject() as RenderBox?)?.size ??
      Size.zero;

  void _onSticks(StickState s) {
    _stick = s.right;
    if (_stick == Offset.zero) return;
    if (!_visible) {
      final size = _size;
      setState(() {
        _visible = true;
        _pos ??= size.center(Offset.zero);
      });
    }
    _keepVisible();
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _tick(Duration now) {
    final last = _lastTick ?? now;
    _lastTick = now;
    if (_stick == Offset.zero) {
      _ticker.stop();
      return;
    }
    final dt = (now - last).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final size = _size;
    // Squared response: fine control near the centre, fast at the edge.
    final speed = size.width / _crossTime * _stick.distance;
    final step = _stick * speed * dt;
    final p = (_pos ?? size.center(Offset.zero)) + step;
    setState(() {
      _pos = Offset(
        p.dx.clamp(0.0, size.width - 1),
        p.dy.clamp(0.0, size.height - 1),
      );
    });
    if (_pointer != null) _send(PointerMoveEvent.new);
    _keepVisible();
  }

  void _keepVisible() {
    _hide?.cancel();
    _hide = Timer(_idle, () {
      if (mounted && _pointer == null) setState(() => _visible = false);
    });
  }

  Offset get _global {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final p = _pos ?? Offset.zero;
    return box == null ? p : box.localToGlobal(p);
  }

  void _send(
    PointerEvent Function({
      required int pointer,
      required int device,
      required Offset position,
      required PointerDeviceKind kind,
      required Duration timeStamp,
    })
    make,
  ) {
    final ts = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    GestureBinding.instance.handlePointerEvent(
      make(
        pointer: _pointer!,
        device: _device,
        position: _global,
        kind: PointerDeviceKind.touch,
        timeStamp: ts,
      ),
    );
  }

  bool _onKey(KeyEvent e) {
    final k = e.logicalKey;
    if (PadKeys.b.contains(k)) {
      if (e is KeyDownEvent) widget.onBack();
      return true;
    }
    if (PadKeys.a.contains(k) && (_visible || _pointer != null)) {
      if (e is KeyDownEvent && _pointer == null) {
        _pointer = _nextPointer++;
        _send(PointerDownEvent.new);
        setState(() {});
      } else if (e is KeyUpEvent && _pointer != null) {
        _send(PointerUpEvent.new);
        setState(() => _pointer = null);
        _keepVisible();
      }
      return true;
    }
    // Back to moving the focus: the pointer would only be in the way.
    if (PadKeys.dpad.contains(k) && e is KeyDownEvent && _visible) {
      if (_pointer == null) setState(() => _visible = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    final pressed = _pointer != null;
    return Listener(
      // A real touch hides the pointer.
      onPointerDown: (e) {
        if (e.device != _device && _visible && _pointer == null) {
          setState(() => _visible = false);
        }
      },
      child: Stack(
        key: _key,
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_visible && pos != null)
            Positioned(
              left: pos.dx - 4,
              top: pos.dy - 3,
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('gamepadCursor'),
                  size: const Size(26, 32),
                  painter: _ArrowPainter(pressed: pressed),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.pressed});
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 32;
    canvas.translate(4, 3);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 24 * s)
      ..lineTo(6.5 * s, 18 * s)
      ..lineTo(11 * s, 27 * s)
      ..lineTo(15 * s, 25 * s)
      ..lineTo(10.5 * s, 16.5 * s)
      ..lineTo(19 * s, 16.5 * s)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(
      path,
      Paint()..color = pressed ? const Color(0xFFFFC107) : Colors.white,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black,
    );
    if (pressed) {
      canvas.drawCircle(
        Offset.zero,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFC107),
      );
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pressed != pressed;
}
