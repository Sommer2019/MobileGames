import 'dart:async';

import 'package:flutter/material.dart';

import '../core/net/messenger.dart';
import '../core/nostr/keys.dart';
import '../core/nostr/relay_pool.dart';
import '../core/services.dart';

/// Shows whether the app reaches the relays and sees its friends, with a
/// test that sends a message to itself through the relays.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  Timer? _refresh;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Sends our presence and waits until it comes back from a relay.
  Future<void> _test() async {
    final s = Services.I;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final watch = Stopwatch()..start();
    final echo = Completer<void>();
    final sub = s.client
        .subscribe({
          'kinds': [Kinds.presence],
          'authors': [s.account.keys.publicKey],
          'since': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2,
        })
        .listen((_) {
          if (!echo.isCompleted) echo.complete();
        });
    // Give the subscription a moment to reach the relays.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    s.presence.announce();
    String result;
    try {
      await echo.future.timeout(const Duration(seconds: 10));
      result = '✅ Nachricht kam nach ${watch.elapsedMilliseconds} ms zurück.';
    } on TimeoutException {
      result =
          '❌ Keine Antwort in 10 s – die Relays sind nicht erreichbar '
          '(Netzwerk, VPN, Werbeblocker oder Firewall?).';
    }
    await sub.cancel();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  String _ago(DateTime? t) {
    if (t == null) return 'noch nicht gesehen';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'vor $s s gesehen';
    return 'vor ${s ~/ 60} min gesehen';
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.I;
    final client = s.client;
    final relays = client is RelayPool ? client.status : const <RelayStatus>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verbindung'),
        actions: [
          if (client is RelayPool)
            IconButton(
              tooltip: 'Neu verbinden',
              icon: const Icon(Icons.sync),
              onPressed: () => client.reconnectNow(force: true),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Relays', style: theme.textTheme.titleMedium),
          Text(
            '${relays.where((r) => r.open).length} von ${relays.length} '
            'verbunden. Eins reicht zum Spielen.',
            style: theme.textTheme.bodySmall,
          ),
          for (final r in relays)
            ListTile(
              dense: true,
              leading: Icon(
                r.open ? Icons.check_circle : Icons.error_outline,
                color: r.open ? Colors.green : theme.colorScheme.error,
              ),
              title: Text(r.url.replaceFirst('wss://', '')),
              subtitle: r.open || r.error == null
                  ? Text(r.open ? 'verbunden' : 'verbindet …')
                  : Text(r.error!, maxLines: 3),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('connectionTest'),
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: const Text('Verbindung testen'),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_testResult!),
            ),
          const Divider(height: 32),
          Text('Freunde', style: theme.textTheme.titleMedium),
          if (s.account.friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Noch keine Freunde.'),
            ),
          for (final f in s.account.friends)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.circle,
                size: 14,
                color: s.presence.isOnline(f.pubkey)
                    ? Colors.green
                    : Colors.grey,
              ),
              title: Text(f.name),
              subtitle: Text(
                '${_ago(s.presence.lastSeen(f.pubkey))} • '
                'ID ${shortCodeFor(f.pubkey)}',
              ),
            ),
          const Divider(height: 32),
          Text(
            'Deine ID: ${shortCodeFor(s.account.keys.publicKey)}\n'
            'Auf beiden Geräten muss beim jeweils anderen genau diese ID '
            'als Freund stehen.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
