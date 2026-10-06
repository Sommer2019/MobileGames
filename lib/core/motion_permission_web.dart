import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _asked = false;

/// Safari on iOS only delivers motion and orientation events (Labyrinth,
/// shaking the dice, motion darts) after the page asked for them during a
/// tap. Called on the first tap; elsewhere this does nothing.
void requestMotionPermission() {
  if (_asked) return;
  _asked = true;
  for (final name in ['DeviceMotionEvent', 'DeviceOrientationEvent']) {
    final value = globalContext[name];
    if (value == null || !value.isA<JSObject>()) continue;
    final type = value as JSObject;
    if (!type.has('requestPermission')) continue;
    try {
      type.callMethod<JSAny?>('requestPermission'.toJS);
    } catch (_) {}
  }
}
