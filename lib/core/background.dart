import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_info.dart';

@pragma('vm:entry-point')
void _startKeepAlive() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

/// The service only exists to keep the app process (and with it the relay
/// connections) alive; the work happens in the normal app code.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps the app reachable for invites and messages while it is in the
/// background (Android). Without an own push server this is the only way:
/// Android otherwise freezes background apps and their connections.
/// A small permanent notification shows that the service is running.
class BackgroundService extends ChangeNotifier {
  BackgroundService._();
  static final BackgroundService I = BackgroundService._();

  static const _prefKey = 'background.enabled';
  bool _enabled = true;
  bool _initialised = false;

  bool get supported => !kIsWeb && Platform.isAndroid && !playStoreBuild;
  bool get enabled => supported && _enabled;

  Future<void> init() async {
    if (!supported || _initialised) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'keep_alive',
          channelName: 'Erreichbarkeit',
          channelDescription:
              'Hält die Verbindung für Einladungen und Nachrichten offen.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
      _initialised = true;
      if (_enabled) await _start();
    } catch (e) {
      debugPrint('Background service unavailable: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!supported) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (value) {
      await _start();
    } else {
      await FlutterForegroundTask.stopService();
    }
    notifyListeners();
  }

  Future<void> _start() async {
    if (!_initialised) return;
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        serviceId: 4711,
        notificationTitle: 'Mobile Games',
        notificationText: 'Online – Einladungen und Nachrichten kommen an',
        callback: _startKeepAlive,
      );
    } catch (e) {
      debugPrint('Could not start background service: $e');
    }
  }

  Future<bool> get ignoringBatteryOptimizations async {
    if (!supported) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  /// Asks Android to exclude the app from battery optimisation, so the
  /// connection also survives longer standby periods.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!supported) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
    notifyListeners();
  }
}
