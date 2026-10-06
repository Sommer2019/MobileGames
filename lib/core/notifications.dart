import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications for invites and chat messages while the app is in
/// the background. (Without an own push server nothing can arrive while the
/// app is completely closed.)
class Notifications {
  Notifications._();
  static final Notifications I = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 1;

  /// Called when the user taps a notification (payload as given to [show]).
  void Function(String payload)? onTap;

  /// Whether the app is currently visible.
  bool get inForeground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Öffnen'),
          windows: WindowsInitializationSettings(
            appName: 'Mobile Games',
            appUserModelId: 'Sommer.MobileGames',
            guid: '6f1d6c2e-3b8a-4d55-9c1e-2a7f0e4b9d13',
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onTap?.call(p);
        },
      );
      _ready = true;
      await requestPermission();
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks for permission (Android 13+, iOS). Returns whether notifications
  /// can be shown.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        await android.requestNotificationsPermission();
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
    return false;
  }

  Future<void> show(String title, String body, {String? payload}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'social',
            'Einladungen & Chat',
            channelDescription: 'Spieleinladungen und Nachrichten von Freunden',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
