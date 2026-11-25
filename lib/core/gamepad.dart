import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Position of both analog sticks, each axis -1..1 (y down), small
/// deflections already cut off.
class StickState {
  const StickState(this.left, this.right);
  static const zero = StickState(Offset.zero, Offset.zero);
  final Offset left;
  final Offset right;
}

/// Analog sticks of gamepads and gaming handhelds (AYN Thor and the like).
///
/// Buttons and the D-pad arrive as normal keys (gameButtonA, arrowUp …),
/// Flutter does not forward stick movements on Android; MainActivity passes
/// them on through a channel.
class Gamepad {
  Gamepad._();
  static final Gamepad I = Gamepad._();

  /// Below this a stick counts as resting (worn sticks drift a little).
  static const deadZone = 0.18;

  final _controller = StreamController<StickState>.broadcast();
  StreamSubscription<dynamic>? _native;
  StickState _state = StickState.zero;

  /// The last known position of the sticks.
  StickState get state => _state;

  /// Whether a stick was ever moved, i.e. a gamepad is in use.
  bool get seen => _seen;
  bool _seen = false;

  Stream<StickState> get sticks {
    _start();
    return _controller.stream;
  }

  void _start() {
    if (_native != null || kIsWeb || !Platform.isAndroid) return;
    _native = const EventChannel('mobilegames/gamepad')
        .receiveBroadcastStream()
        .listen((e) {
          final v = [for (final x in e as List) (x as num).toDouble()];
          if (v.length < 6) return;
          // Right stick: z/rz on most devices, rx/ry on some.
          var right = Offset(v[2], v[3]);
          if (right.distance < deadZone) right = Offset(v[4], v[5]);
          add(StickState(Offset(v[0], v[1]), right));
        }, onError: (Object _) {});
  }

  /// Feeds a stick position (from the platform, or tests).
  @visibleForTesting
  void add(StickState raw) {
    final s = StickState(_cut(raw.left), _cut(raw.right));
    if (s.left != Offset.zero || s.right != Offset.zero) _seen = true;
    _state = s;
    _controller.add(s);
  }

  static Offset _cut(Offset o) {
    final d = o.distance;
    if (d < deadZone || !d.isFinite) return Offset.zero;
    // Rescale so movement starts gently just outside the dead zone.
    final scaled = min(1.0, (d - deadZone) / (1 - deadZone));
    return o / d * scaled;
  }
}

/// Gamepad buttons, also under their keyboard names on some devices.
abstract final class PadKeys {
  static final a = {
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.gameButtonRight1,
  };
  static final b = {LogicalKeyboardKey.gameButtonB};
  static final dpad = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
}
