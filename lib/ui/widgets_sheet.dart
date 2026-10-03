import 'dart:io';

import 'package:flutter/material.dart';

import '../core/home_widgets.dart';

/// Explains the home screen widgets and adds them directly where the
/// launcher supports it.
Future<void> showWidgetsSheet(BuildContext context) async {
  final canPin = await HomeWidgets.canPin();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Widgets für den Startbildschirm',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final (title, text, android) in const [
              (
                '🎲 Würfel',
                '1–6 Würfel, antippen zum Würfeln',
                HomeWidgets.androidDice,
              ),
              (
                '🎮 Spieleabend',
                'Nachrichten, Freunde online, letzte Spiele',
                HomeWidgets.androidGameNight,
              ),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: Text(text),
                trailing: canPin
                    ? FilledButton(
                        onPressed: () {
                          Navigator.pop(c);
                          HomeWidgets.pin(android);
                        },
                        child: const Text('Hinzufügen'),
                      )
                    : null,
              ),
            const SizedBox(height: 8),
            Text(
              Platform.isIOS
                  ? 'Startbildschirm lange drücken → „+“ → „Mobile Games“ suchen.'
                  : 'Falls „Hinzufügen“ nicht klappt: Startbildschirm lange '
                        'drücken → Widgets → „Mobile Games“. Bei Xiaomi steht '
                        'die App oft weiter unten in der Widget-Liste; außerdem '
                        'unter Einstellungen → Apps → Mobile Games „Autostart“ '
                        'erlauben, damit die Widgets reagieren.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
