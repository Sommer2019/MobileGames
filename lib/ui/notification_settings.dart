import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/background.dart';
import '../core/notifications.dart';

/// Settings that decide whether invites and messages reach the player.
class NotificationSettingsCard extends StatefulWidget {
  const NotificationSettingsCard({super.key});

  @override
  State<NotificationSettingsCard> createState() =>
      _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<NotificationSettingsCard> {
  final bg = BackgroundService.I;
  bool? _batteryOk;

  bool get _isIos => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    bg.addListener(_refresh);
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    final ok = await bg.ignoringBatteryOptimizations;
    if (mounted) setState(() => _batteryOk = ok);
  }

  @override
  void dispose() {
    bg.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
    _checkBattery();
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await Notifications.I.requestPermission();
    if (!allowed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Benachrichtigungen sind blockiert – bitte in den '
            'Systemeinstellungen für Mobile Games erlauben.',
          ),
        ),
      );
      return;
    }
    // Shown with a delay so you can leave the app and see it arrive.
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Test kommt in 5 Sekunden – du kannst die App jetzt verlassen.',
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 5));
    await Notifications.I.show('Test', 'Benachrichtigungen funktionieren ✓');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text('Benachrichtigungen'),
              subtitle: const Text(
                'Einladungen, Freundschaftsanfragen und Nachrichten',
              ),
              trailing: OutlinedButton(
                key: const ValueKey('testNotification'),
                onPressed: _test,
                child: const Text('Testen'),
              ),
            ),
            if (bg.supported) ...[
              SwitchListTile(
                secondary: const Icon(Icons.wifi_tethering),
                title: const Text('Im Hintergrund erreichbar'),
                subtitle: const Text(
                  'Hält die Verbindung offen, solange die App im Hintergrund '
                  'läuft (kleine dauerhafte Benachrichtigung).',
                ),
                value: bg.enabled,
                onChanged: bg.setEnabled,
              ),
              if (_batteryOk == false)
                ListTile(
                  leading: const Icon(
                    Icons.battery_alert,
                    color: Colors.orange,
                  ),
                  title: const Text('Akku-Optimierung ausschalten'),
                  subtitle: const Text(
                    'Sonst trennt Android die Verbindung nach einiger Zeit.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: bg.requestIgnoreBatteryOptimizations,
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                _isIos || !bg.supported
                    ? 'Hinweis: Apps im Hintergrund bleiben nur kurz aktiv. '
                          'Ohne eigenen Push-Server kommen Benachrichtigungen '
                          'daher nur, solange die App geöffnet ist oder gerade '
                          'erst verlassen wurde. Nachrichten werden beim nächsten '
                          'Öffnen nachgeladen.'
                    : 'Wird die App ganz geschlossen (aus der Übersicht '
                          'gewischt), kommen keine Benachrichtigungen – '
                          'Nachrichten werden beim nächsten Öffnen nachgeladen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
