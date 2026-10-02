package de.sommer2019.mobile_games

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // ANDROID_ID: stays the same for this app on this phone across
    // reinstalls (same signing key), used to recover the account.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilegames/device")
        .setMethodCallHandler { call, result ->
          if (call.method == "androidId") {
            result.success(Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
          } else {
            result.notImplemented()
          }
        }
  }
}
