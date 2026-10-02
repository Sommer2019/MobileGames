import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:volume_controller/volume_controller.dart';

enum KonamiInput { up, down, left, right, volumeUp, volumeDown, plugIn }

/// The secret: swipe ↑ ↑ ↓ ↓ ← → ← →, volume up, volume down, plug in.
class KonamiCode {
  KonamiCode({this.timeout = const Duration(seconds: 60)});

  static const sequence = [
    KonamiInput.up,
    KonamiInput.up,
    KonamiInput.down,
    KonamiInput.down,
    KonamiInput.left,
    KonamiInput.right,
    KonamiInput.left,
    KonamiInput.right,
    KonamiInput.volumeUp,
    KonamiInput.volumeDown,
    KonamiInput.plugIn,
  ];

  /// The whole code has to be entered within this time.
  final Duration timeout;

  int _pos = 0;
  DateTime? _started;

  int get progress => _pos;

  /// Feeds one input. Returns true when the code is complete.
  bool add(KonamiInput input, {DateTime? now}) {
    now ??= DateTime.now();
    if (_pos > 0 && now.difference(_started!) > timeout) _pos = 0;
    if (sequence[_pos] == input) {
      if (_pos == 0) _started = now;
      _pos++;
      if (_pos == sequence.length) {
        _pos = 0;
        return true;
      }
      return false;
    }
    // A wrong input may itself be the start of a new attempt (and ↑ ↑ ↑
    // still works, like in the original).
    if (_pos == 2 && input == KonamiInput.up) return false;
    _pos = 0;
    if (input == sequence.first) {
      _started = now;
      _pos = 1;
    }
    return false;
  }
}

/// Listens for swipes on [child], the volume buttons and the charger and
/// calls [onUnlocked] when the [KonamiCode] was entered.
class KonamiDetector extends StatefulWidget {
  const KonamiDetector({
    super.key,
    required this.child,
    required this.onUnlocked,
    this.batteryStates,
  });

  final Widget child;
  final VoidCallback onUnlocked;

  /// Charger states; by default from the device.
  @visibleForTesting
  final Stream<BatteryState>? batteryStates;

  @override
  State<KonamiDetector> createState() => _KonamiDetectorState();
}

class _KonamiDetectorState extends State<KonamiDetector> {
  final KonamiCode _code = KonamiCode();
  final Map<int, Offset> _down = {};
  StreamSubscription<double>? _volume;
  StreamSubscription<BatteryState>? _battery;
  double? _lastVolume;
  bool? _plugged;
  final Map<KonamiInput, DateTime> _lastVolumeInput = {};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    try {
      VolumeController.instance.showSystemUI = true;
      _volume = VolumeController.instance.addListener((v) {
        final last = _lastVolume;
        _lastVolume = v;
        if (last == null || (v - last).abs() < 1e-4) return;
        _volumeInput(v > last ? KonamiInput.volumeUp : KonamiInput.volumeDown);
      })..onError((Object _) {});
    } catch (_) {}
    try {
      final states = widget.batteryStates ?? Battery().onBatteryStateChanged;
      _battery = states.listen((s) {
        final plugged =
            s == BatteryState.charging ||
            s == BatteryState.full ||
            s == BatteryState.connectedNotCharging;
        if (s == BatteryState.unknown) return;
        final was = _plugged;
        _plugged = plugged;
        if (was == false && plugged) _input(KonamiInput.plugIn);
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _volume?.cancel();
    _battery?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (e.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      _volumeInput(KonamiInput.volumeUp);
    } else if (e.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      _volumeInput(KonamiInput.volumeDown);
    }
    // Never swallow the key: the volume should still change.
    return false;
  }

  /// A button press may arrive both as key and as volume change.
  void _volumeInput(KonamiInput input) {
    final now = DateTime.now();
    final last = _lastVolumeInput[input];
    _lastVolumeInput[input] = now;
    if (last != null && now.difference(last).inMilliseconds < 400) return;
    _input(input);
  }

  void _input(KonamiInput input) {
    if (_code.add(input)) {
      HapticFeedback.heavyImpact();
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _down[e.pointer] = e.position,
      onPointerCancel: (e) => _down.remove(e.pointer),
      onPointerUp: (e) {
        final start = _down.remove(e.pointer);
        if (start == null) return;
        final d = e.position - start;
        if (d.distance < 60) return;
        if (d.dx.abs() > d.dy.abs() * 1.5) {
          _input(d.dx > 0 ? KonamiInput.right : KonamiInput.left);
        } else if (d.dy.abs() > d.dx.abs() * 1.5) {
          _input(d.dy > 0 ? KonamiInput.down : KonamiInput.up);
        }
      },
      child: widget.child,
    );
  }
}
