import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vibration/vibration.dart';
import 'package:volume_controller/volume_controller.dart';

import 'platform_caps.dart';

enum KonamiInput { up, down, left, right, volumeUp, volumeDown, plugIn }

/// Whether a chat message spells the Konami code, e.g. "↑↑↓↓←→←→BA",
/// "uuddlrlrba" or "up up down down left right left right b a".
bool isKonamiText(String text) {
  var s = text.toLowerCase();
  for (final (from, to) in const [
    ('↑', 'u'),
    ('↓', 'd'),
    ('←', 'l'),
    ('→', 'r'),
    ('⬆', 'u'),
    ('⬇', 'd'),
    ('⬅', 'l'),
    ('➡', 'r'),
  ]) {
    s = s.replaceAll(from, to);
  }
  s = s.replaceAll(RegExp('[^a-z]'), '');
  s = s
      .replaceAll('down', 'd')
      .replaceAll('up', 'u')
      .replaceAll('left', 'l')
      .replaceAll('right', 'r')
      .replaceAll('start', '');
  return s == 'uuddlrlrba' || s == 'uuddlrlr';
}

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

  static bool _isVolume(KonamiInput i) =>
      i == KonamiInput.volumeUp || i == KonamiInput.volumeDown;

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
    // Some phones need two presses before the volume changes (the first
    // only shows the slider): repeated volume presses count once.
    if (_pos > 0 && _isVolume(input) && sequence[_pos - 1] == input) {
      return false;
    }
    _pos = 0;
    if (input == sequence.first) {
      _started = now;
      _pos = 1;
    }
    return false;
  }
}

/// Vibration rhythm of the code itself: ↑↑ ↓↓ ←→←→, then the accented
/// "B A" and a long final buzz. Alternating pause / vibration in ms.
const konamiJingle = [
  0, 60, 80, 60, // ↑ ↑
  200, 60, 80, 60, // ↓ ↓
  200, 50, 70, 50, 70, 50, 70, 50, // ← → ← →
  220, 140, 90, 140, // B A
  260, 600, // ta-daa
];

/// Strength (1-255) for each entry of [konamiJingle]; pauses are 0.
const konamiJingleIntensities = [
  0, 160, 0, 160, //
  0, 160, 0, 160, //
  0, 120, 0, 120, 0, 120, 0, 120, //
  0, 255, 0, 255, //
  0, 255, //
];

/// Plays [konamiJingle] on the vibration motor (independent of the
/// system's touch feedback setting). Falls back to haptic feedback.
Future<void> playKonamiJingle() async {
  try {
    if (await Vibration.hasVibrator()) {
      final amplitude = await Vibration.hasAmplitudeControl();
      await Vibration.vibrate(
        pattern: konamiJingle,
        intensities: amplitude ? konamiJingleIntensities : const [],
      );
      return;
    }
  } catch (_) {}
  await HapticFeedback.heavyImpact();
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
    // Volume keys and charger are not visible in the browser or on a
    // computer.
    if ((kIsWeb || isDesktop) && widget.batteryStates == null) return;
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
      playKonamiJingle();
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
