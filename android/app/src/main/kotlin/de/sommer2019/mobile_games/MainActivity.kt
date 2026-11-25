package de.sommer2019.mobile_games

import android.content.res.Configuration
import android.provider.Settings
import android.view.Surface
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  /// Receives the analog sticks of gamepads and handhelds (AYN Thor,
  /// Retroid, Odin …) while the app listens.
  private var gamepadSink: EventChannel.EventSink? = null

  /// The lower screen of dual-screen handhelds.
  private var companion: CompanionScreen? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // ANDROID_ID: stays the same for this app on this phone across
    // reinstalls (same signing key), used to recover the account.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilegames/device")
        .setMethodCallHandler { call, result ->
          if (call.method == "androidId") {
            result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
          } else if (call.method == "naturalLandscape") {
            // Handhelds like the AYN Thor are landscape when not rotated.
            @Suppress("DEPRECATION")
            val rotation = windowManager.defaultDisplay.rotation
            val upright = rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_180
            val landscape =
                resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            result.success(upright == landscape)
          } else {
            result.notImplemented()
          }
        }
    companion = CompanionScreen(this, flutterEngine.dartExecutor.binaryMessenger)
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilegames/gamepad")
        .setStreamHandler(
            object : EventChannel.StreamHandler {
              override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                gamepadSink = events
              }

              override fun onCancel(arguments: Any?) {
                gamepadSink = null
              }
            })
  }

  override fun onStart() {
    super.onStart()
    companion?.start()
  }

  override fun onStop() {
    companion?.stop()
    super.onStop()
  }

  override fun onDestroy() {
    companion?.destroy()
    companion = null
    super.onDestroy()
  }

  /// Flutter itself ignores joystick axes. They are passed on as
  /// [left x, left y, z, rz, rx, ry] – the right stick is z/rz on most
  /// devices, rx/ry on some. The event is not consumed, so Android still
  /// turns the left stick and the hat into D-pad keys.
  override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
    val sink = gamepadSink
    if (sink != null &&
        event.isFromSource(InputDevice.SOURCE_JOYSTICK) &&
        event.actionMasked == MotionEvent.ACTION_MOVE) {
      sink.success(
          doubleArrayOf(
              event.getAxisValue(MotionEvent.AXIS_X).toDouble(),
              event.getAxisValue(MotionEvent.AXIS_Y).toDouble(),
              event.getAxisValue(MotionEvent.AXIS_Z).toDouble(),
              event.getAxisValue(MotionEvent.AXIS_RZ).toDouble(),
              event.getAxisValue(MotionEvent.AXIS_RX).toDouble(),
              event.getAxisValue(MotionEvent.AXIS_RY).toDouble(),
          ))
    }
    return super.dispatchGenericMotionEvent(event)
  }
}
