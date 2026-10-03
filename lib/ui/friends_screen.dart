import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/names.dart';
import '../core/services.dart';
import 'chat_view.dart';
import 'friend_code_widgets.dart';
import 'notification_settings.dart';
import 'widgets_sheet.dart';

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
    services.chat.addListener(_refresh);
    services.friendRequests.addListener(_refresh);
  }

  @override
  void dispose() {
    services.account.removeListener(_refresh);
    services.presence.removeListener(_refresh);
    services.chat.removeListener(_refresh);
    services.friendRequests.removeListener(_refresh);
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
          maxLength: maxNameLength,
          inputFormatters: [NameInputFormatter()],
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
    var busy = false;
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
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Freundescode (z. B. K7Q2M-9XW4P)',
                  errorText: error,
                  errorMaxLines: 3,
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
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('scanQr'),
                onPressed: () async {
                  final scanned = await Navigator.push<String>(
                    c,
                    MaterialPageRoute(builder: (_) => const QrScanScreen()),
                  );
                  if (scanned != null) code.text = scanned;
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QR-Code scannen'),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialog(() {
                        busy = true;
                        error = null;
                      });
                      final err = await services.friendRequests.addByCode(
                        code.text,
                        name: name.text.trim().isEmpty
                            ? null
                            : name.text.trim(),
                      );
                      if (err == null) {
                        if (c.mounted) Navigator.pop(c);
                      } else if (c.mounted) {
                        setDialog(() {
                          busy = false;
                          error = err;
                        });
                      }
                    },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFriend(String pubkey, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$name entfernen?'),
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
    if (ok == true) await services.account.removeFriend(pubkey);
  }

  void _openChat(String pubkey) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => FriendChatScreen(pubkey: pubkey)),
  );

  Widget _avatar(String name, String pubkey) => Stack(
    children: [
      CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
      Positioned(
        right: 0,
        bottom: 0,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: services.presence.isOnline(pubkey)
                ? Colors.green
                : Colors.grey,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final account = services.account;
    final chat = services.chat;
    final friends = [...account.friends]
      ..sort((a, b) {
        final oa = services.presence.isOnline(a.pubkey);
        final ob = services.presence.isOnline(b.pubkey);
        if (oa != ob) return oa ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final strangers = chat.conversations
        .where((p) => account.friend(p) == null)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Freund wählen' : 'Konto & Freunde'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add),
        label: const Text('Freund'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
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
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
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
                        MyFriendCode(account: account),
                        const SizedBox(height: 8),
                        Text(
                          'Dein Konto ist ein Schlüsselpaar, das nur auf diesem '
                          'Gerät gespeichert ist – kein Server, keine E-Mail, kein '
                          'Passwort. Teile den Code oder zeig den QR-Code – dein '
                          'Freund bekommt eine Anfrage, und nach dem Annehmen seid '
                          'ihr gegenseitig befreundet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              if (!widget.pickMode) const NotificationSettingsCard(),
              if (!widget.pickMode)
                Card(
                  child: ListTile(
                    key: const ValueKey('widgetsTile'),
                    leading: const Icon(Icons.widgets_outlined),
                    title: const Text('Widgets für den Startbildschirm'),
                    subtitle: const Text('Würfel und Spieleabend'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showWidgetsSheet(context),
                  ),
                ),
              if (services.friendRequests.pending.isNotEmpty &&
                  !widget.pickMode) ...[
                const SizedBox(height: 8),
                Text(
                  'Freundschaftsanfragen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final e in services.friendRequests.pending.entries)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_add),
                      ),
                      title: Text(e.value),
                      subtitle: const Text('möchte mit dir befreundet sein'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Ablehnen',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                services.friendRequests.declineRequest(e.key),
                          ),
                          IconButton.filled(
                            key: ValueKey('accept-${e.key}'),
                            tooltip: 'Annehmen',
                            icon: const Icon(Icons.check),
                            onPressed: () =>
                                services.friendRequests.acceptRequest(e.key),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                'Freunde (${friends.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Noch keine Freunde. Tippe auf „Freund“ und füge einen '
                    'Freundescode ein.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final f in friends)
                Card(
                  child: ListTile(
                    leading: _avatar(f.name, f.pubkey),
                    title: Text(
                      services.presence.hasBadge(f.pubkey)
                          ? '${f.name} 🎮'
                          : f.name,
                    ),
                    subtitle: Text(
                      chat.messages(f.pubkey).isNotEmpty
                          ? chat.messages(f.pubkey).last.text
                          : services.presence.isOnline(f.pubkey)
                          ? 'Online'
                          : 'Offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: widget.pickMode
                        ? () => Navigator.pop(context, f.pubkey)
                        : () => _openChat(f.pubkey),
                    trailing: widget.pickMode
                        ? const Icon(Icons.send)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Chat',
                                onPressed: () => _openChat(f.pubkey),
                                icon: Badge(
                                  isLabelVisible: chat.unread(f.pubkey) > 0,
                                  label: Text('${chat.unread(f.pubkey)}'),
                                  child: const Icon(Icons.chat_bubble_outline),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (_) =>
                                    _removeFriend(f.pubkey, f.name),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Entfernen'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              if (strangers.isNotEmpty && !widget.pickMode) ...[
                const SizedBox(height: 16),
                Text(
                  'Nachrichten von anderen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final p in strangers)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.mail)),
                      title: Text(chat.nameOf(p) ?? 'Unbekannt'),
                      subtitle: Text(
                        chat.messages(p).last.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openChat(p),
                      trailing: Badge(
                        isLabelVisible: chat.unread(p) > 0,
                        label: Text('${chat.unread(p)}'),
                        child: IconButton(
                          tooltip: 'Als Freund hinzufügen',
                          icon: const Icon(Icons.person_add_alt),
                          onPressed: () => services.friendRequests.addByCode(
                            p,
                            name: chat.nameOf(p),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One-to-one chat with a friend.
class FriendChatScreen extends StatefulWidget {
  const FriendChatScreen({super.key, required this.pubkey});
  final String pubkey;

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final services = Services.I;

  @override
  void initState() {
    super.initState();
    services.chat.openConversation = widget.pubkey;
    services.chat.markRead(widget.pubkey);
    services.chat.addListener(_changed);
    services.presence.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    services.chat.markRead(widget.pubkey);
    setState(() {});
  }

  @override
  void dispose() {
    if (services.chat.openConversation == widget.pubkey) {
      services.chat.openConversation = null;
    }
    services.chat.removeListener(_changed);
    services.presence.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friend = services.account.friend(widget.pubkey);
    final name =
        friend?.name ?? services.chat.nameOf(widget.pubkey) ?? 'Unbekannt';
    final online = services.presence.isOnline(widget.pubkey);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name),
            if (friend != null)
              Text(
                online
                    ? 'Online'
                    : 'Offline – bekommt die Nachricht beim nächsten Start',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ChatView(
            showAuthors: false,
            emptyText: 'Schreib $name eine Nachricht!',
            lines: [
              for (final m in services.chat.messages(widget.pubkey))
                ChatEntry(
                  mine: m.mine,
                  author: m.mine ? 'Du' : name,
                  text: m.text,
                  time: m.time,
                ),
            ],
            quickReplies: const [
              'Lust auf eine Runde?',
              'Bin gleich da!',
              '👍',
            ],
            onSend: (t) => services.chat.send(
              widget.pubkey,
              t,
              myName: services.account.name,
            ),
          ),
        ),
      ),
    );
  }
}
