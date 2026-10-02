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
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onTap?.call(p);
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
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
        ),
      );
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
