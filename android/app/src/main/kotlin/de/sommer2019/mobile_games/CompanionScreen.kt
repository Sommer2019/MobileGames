package de.sommer2019.mobile_games

import android.app.Activity
import android.app.ActivityOptions
import android.app.Presentation
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The second screen of dual-screen handhelds such as the AYN Thor.
 *
 * A second Flutter engine runs `companionMain` (lib/main.dart) and is shown
 * on the other display, as a [Presentation] (does not take the focus, so the
 * gamepad keeps controlling the game on top) or, where the system does not
 * allow that, as an activity launched on that display. Pages from the game
 * and taps from below are passed on between the two engines.
 */
class CompanionScreen(private val activity: Activity, mainMessenger: BinaryMessenger) :
    DisplayManager.DisplayListener {

  private val main = MethodChannel(mainMessenger, CHANNEL)
  private val displays = activity.getSystemService(DisplayManager::class.java)
  private var engine: FlutterEngine? = null
  private var channel: MethodChannel? = null
  private var presentation: Presentation? = null
  private var view: FlutterView? = null
  private var activityShown = false
  private var lastPage: String? = null
  private var enabled = true
  private var started = false

  init {
    main.setMethodCallHandler { call, result ->
      when (call.method) {
        "publish" -> {
          lastPage = call.arguments as? String
          channel?.invokeMethod("page", lastPage)
          result.success(null)
        }
        "available" -> result.success(target() != null)
        "setEnabled" -> {
          enabled = call.arguments == true
          if (enabled) show() else hide()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  fun start() {
    started = true
    displays.registerDisplayListener(this, Handler(Looper.getMainLooper()))
    show()
  }

  fun stop() {
    started = false
    displays.unregisterDisplayListener(this)
    hide()
  }

  fun destroy() {
    stop()
    FlutterEngineCache.getInstance().remove(ENGINE_ID)
    engine?.destroy()
    engine = null
    channel = null
  }

  private fun ownDisplayId(): Int =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        activity.display?.displayId ?: Display.DEFAULT_DISPLAY
      } else {
        @Suppress("DEPRECATION") activity.windowManager.defaultDisplay.displayId
      }

  /** The other screen; none while the app itself runs on the lower one. */
  private fun target(): Display? {
    val own = ownDisplayId()
    if (own != Display.DEFAULT_DISPLAY) return null
    val preferred = displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).toList()
    return (preferred + displays.displays.toList()).firstOrNull {
      it.displayId != own && it.isValid && (it.flags and Display.FLAG_PRIVATE) == 0
    }
  }

  private fun engine(): FlutterEngine {
    engine?.let { return it }
    val loader = FlutterInjector.instance().flutterLoader()
    val e =
        FlutterEngineGroup(activity)
            .createAndRunEngine(
                FlutterEngineGroup.Options(activity)
                    .setDartEntrypoint(
                        DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "companionMain"))
                    .setAutomaticallyRegisterPlugins(false))
    channel =
        MethodChannel(e.dartExecutor.binaryMessenger, CHANNEL).apply {
          setMethodCallHandler { call, result ->
            when (call.method) {
              "ready" -> result.success(lastPage)
              "action" -> {
                main.invokeMethod("action", call.arguments)
                result.success(null)
              }
              else -> result.notImplemented()
            }
          }
        }
    FlutterEngineCache.getInstance().put(ENGINE_ID, e)
    engine = e
    return e
  }

  private fun show() {
    if (!started || !enabled || presentation != null || activityShown) return
    val display = target() ?: return
    val e = engine()
    try {
      val p =
          object : Presentation(activity, display) {
            override fun onCreate(savedInstanceState: Bundle?) {
              super.onCreate(savedInstanceState)
              // Keys stay with the game on the main screen; touches still work.
              window?.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
              val v = FlutterView(context)
              setContentView(v)
              v.attachToFlutterEngine(e)
              view = v
            }
          }
      p.setOnDismissListener {
        view?.detachFromFlutterEngine()
        view = null
      }
      p.show()
      presentation = p
    } catch (ex: Exception) {
      // E.g. the display does not take presentations: an activity there.
      Log.w(TAG, "Presentation failed, starting an activity instead", ex)
      presentation = null
      try {
        val intent =
            FlutterActivity.withCachedEngine(ENGINE_ID)
                .build(activity)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(display.displayId)
        activity.startActivity(intent, options.toBundle())
        activityShown = true
      } catch (ex2: Exception) {
        Log.w(TAG, "No second screen", ex2)
        return
      }
    }
    e.lifecycleChannel.appIsResumed()
    main.invokeMethod("available", true)
  }

  private fun hide() {
    val was = presentation != null || activityShown
    presentation?.dismiss()
    presentation = null
    if (activityShown) {
      // The activity below closes itself (SystemNavigator.pop).
      channel?.invokeMethod("close", null)
      activityShown = false
    }
    engine?.lifecycleChannel?.appIsPaused()
    if (was || !enabled) main.invokeMethod("available", target() != null)
  }

  override fun onDisplayAdded(displayId: Int) {
    main.invokeMethod("available", target() != null)
    show()
  }

  override fun onDisplayRemoved(displayId: Int) {
    if (presentation?.display?.displayId == displayId) {
      presentation?.dismiss()
      presentation = null
    }
    main.invokeMethod("available", target() != null)
  }

  override fun onDisplayChanged(displayId: Int) {}

  companion object {
    private const val TAG = "CompanionScreen"
    private const val CHANNEL = "mobilegames/companion"
    const val ENGINE_ID = "companion"
  }
}
