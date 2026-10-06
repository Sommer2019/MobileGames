import 'package:flutter/material.dart';

import '../core/secrets.dart';

/// The secret menu behind the Konami code.
Future<void> showSecretsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: Secrets.I,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '🎮 Geheimnisse',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Freigeschaltet mit dem Geheimcode. Deine Freunde sehen '
                  'jetzt ein 🎮 neben deinem Namen.',
                ),
              ),
              for (final s in Secret.values)
                SwitchListTile(
                  key: ValueKey('secret-${s.name}'),
                  title: Text(s.title),
                  subtitle: Text(s.description),
                  value: Secrets.I.isOn(s),
                  onChanged: (v) => Secrets.I.set(s, v),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
