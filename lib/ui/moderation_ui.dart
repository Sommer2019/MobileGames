import 'package:flutter/material.dart';

import '../core/moderation.dart';
import '../core/services.dart';

/// Asks for a reason and sends the report about [name].
Future<void> reportPlayer(
  BuildContext context, {
  required String name,
  String? pubkey,
  required List<String> messages,
}) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('$name melden'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Moderation.reportEmail.isNotEmpty
                ? 'Die Meldung mit den letzten Nachrichten geht per E-Mail '
                      'an den Entwickler.'
                : 'Die Meldung mit den letzten Nachrichten wird als '
                      'GitHub-Issue an den Entwickler geschickt.',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('reportReason'),
            controller: reason,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Was ist passiert? (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('reportSend'),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Melden'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final sent = await Moderation.sendReport(
    'Meldung: $name',
    Moderation.reportText(
      name: name,
      pubkey: pubkey,
      messages: messages,
      reason: reason.text.trim(),
    ),
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        sent
            ? 'Danke! Bitte die vorbereitete Meldung noch absenden.'
            : 'Keine E-Mail-App gefunden.',
      ),
    ),
  );
}

/// Blocks [pubkey] after asking: removes the friend and the conversation.
/// Returns true if blocked.
Future<bool> blockPlayer(
  BuildContext context, {
  required String pubkey,
  required String name,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('$name blockieren?'),
      content: const Text(
        'Du bekommst keine Nachrichten, Einladungen und Freundschafts'
        'anfragen mehr von diesem Spieler. Der Chat wird gelöscht. '
        'Aufheben kannst du das unter Konto & Freunde.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('blockConfirm'),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Blockieren'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await Moderation.I.block(pubkey, name);
  if (Services.isReady) {
    final s = Services.I;
    await s.account.removeFriend(pubkey);
    s.chat.deleteConversation(pubkey);
  }
  return true;
}

/// Card listing blocked players with a way to unblock them.
class BlockedPlayersCard extends StatelessWidget {
  const BlockedPlayersCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Moderation.I,
      builder: (context, _) {
        final blocked = Moderation.I.blocked;
        if (blocked.isEmpty) return const SizedBox.shrink();
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.block),
            title: Text('Blockiert (${blocked.length})'),
            children: [
              for (final e in blocked.entries)
                ListTile(
                  title: Text(e.value),
                  trailing: TextButton(
                    onPressed: () => Moderation.I.unblock(e.key),
                    child: const Text('Aufheben'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
