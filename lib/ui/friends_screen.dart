import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services.dart';

/// Account (name, friend code) and friend list. In [pickMode] tapping a
/// friend returns their public key.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final services = Services.I;

  @override
  void initState() {
    super.initState();
    services.account.addListener(_refresh);
    services.presence.addListener(_refresh);
  }

  @override
  void dispose() {
    services.account.removeListener(_refresh);
    services.presence.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: services.account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dein Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(hintText: 'Spielername'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (name != null) await services.account.setName(name);
  }

  Future<void> _addFriend() async {
    final code = TextEditingController();
    final name = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: const Text('Freund hinzufügen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: 'Freundescode (npub1…)',
                  errorText: error,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) code.text = data!.text!.trim();
                    },
                  ),
                ),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                final err = await services.account.addFriend(
                  code.text,
                  name: name.text.trim().isEmpty ? null : name.text.trim(),
                );
                if (err == null) {
                  if (c.mounted) Navigator.pop(c);
                } else {
                  setDialog(() => error = err);
                }
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = services.account;
    final friends = [...account.friends]
      ..sort((a, b) {
        final oa = services.presence.isOnline(a.pubkey),
            ob = services.presence.isOnline(b.pubkey);
        if (oa != ob) return oa ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Freund einladen' : 'Konto & Freunde'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add),
        label: const Text('Freund'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          if (!widget.pickMode)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                        account.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      subtitle: const Text('Dein Spielername'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: _editName,
                      ),
                    ),
                    const Text('Dein Freundescode'),
                    const SizedBox(height: 4),
                    SelectableText(
                      account.friendCode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: account.friendCode),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Freundescode kopiert'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Kopieren'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dein Konto ist ein Schlüsselpaar, das nur auf diesem Gerät gespeichert ist – '
                      'kein Server, keine E-Mail, kein Passwort. Teile den Code mit Freunden, '
                      'damit sie dich hinzufügen können.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Freunde (${friends.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine Freunde. Tippe auf „Freund“ und füge einen Freundescode ein.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final f in friends)
            Card(
              child: ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(
                      child: Text(
                        f.name.isEmpty ? '?' : f.name[0].toUpperCase(),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: services.presence.isOnline(f.pubkey)
                              ? Colors.green
                              : Colors.grey,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(f.name),
                subtitle: Text(
                  services.presence.isOnline(f.pubkey) ? 'Online' : 'Offline',
                ),
                onTap: widget.pickMode
                    ? () => Navigator.pop(context, f.pubkey)
                    : null,
                trailing: widget.pickMode
                    ? const Icon(Icons.send)
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text('${f.name} entfernen?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Nein'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Entfernen'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) await account.removeFriend(f.pubkey);
                        },
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
