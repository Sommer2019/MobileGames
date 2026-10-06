import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/platform_caps.dart';
import '../core/account_transfer.dart';
import '../core/services.dart';
import 'friend_code_widgets.dart';

/// Takes the account to a new phone: the old phone shows a code, the new
/// one scans it.
class AccountTransferScreen extends StatefulWidget {
  const AccountTransferScreen({super.key});

  @override
  State<AccountTransferScreen> createState() => _AccountTransferScreenState();
}

class _AccountTransferScreenState extends State<AccountTransferScreen> {
  bool _showCode = false;
  final _input = TextEditingController();
  String? _error;

  String get _myKey => Services.I.account.keys.privateKey;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Geheimen Code anzeigen?'),
        content: const Text(
          'Wer diesen Code hat, ist in der App du: er kann in deinem Namen '
          'schreiben und deine Nachrichten lesen. Zeig ihn nur deinem '
          'eigenen neuen Handy – kein Screenshot, nicht verschicken.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('revealCode'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Anzeigen'),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => _showCode = true);
  }

  Future<void> _scan() async {
    final v = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (v != null) await _take(v);
  }

  Future<void> _take(String code) async {
    final key = AccountTransfer.parse(code);
    if (key == null) {
      setState(() => _error = 'Das ist kein Konto-Code.');
      return;
    }
    if (key == _myKey) {
      setState(() => _error = 'Das ist schon das Konto dieses Handys.');
      return;
    }
    setState(() => _error = null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Konto übernehmen?'),
        content: const Text(
          'Das bisherige Konto auf diesem Handy wird ersetzt (seine Freunde '
          'und Chats sind dann weg). Name und Freunde des übernommenen '
          'Kontos werden nach dem Neustart wiederhergestellt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('adoptConfirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AccountTransfer.adopt(key, client: Services.I.client);
    if (!mounted) return;
    final android = !kIsWeb && Platform.isAndroid;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Konto übernommen'),
        content: Text(
          android
              ? 'Die App wird jetzt beendet. Öffne sie einfach wieder – '
                    'dann bist du mit dem übernommenen Konto da.'
              : 'Bitte schließe die App jetzt ganz (in der App-Übersicht '
                    'nach oben wischen) und öffne sie wieder.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (android) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Konto übertragen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Neues Handy?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Dein Konto hängt an diesem Gerät. Damit Name und Freunde '
            'mitkommen: auf dem alten Handy den Code anzeigen und auf dem '
            'neuen scannen. Spielstände und Chatverläufe bleiben auf dem '
            'alten Handy.',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Auf dem alten Handy',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (!_showCode)
                    OutlinedButton.icon(
                      key: const ValueKey('showTransferCode'),
                      onPressed: _reveal,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Konto-Code anzeigen'),
                    )
                  else ...[
                    Center(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(12),
                        child: QrImageView(
                          data: AccountTransfer.qrPayload(_myKey),
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      AccountTransfer.codeFor(_myKey),
                      key: const ValueKey('transferCode'),
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _showCode = false),
                      icon: const Icon(Icons.visibility_off),
                      label: const Text('Verbergen'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2. Auf dem neuen Handy',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (canScanQr)
                    FilledButton.icon(
                      onPressed: _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Code scannen'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('transferInput'),
                    controller: _input,
                    decoration: InputDecoration(
                      labelText: 'oder Code eingeben (mgkonto1…)',
                      errorText: _error,
                      suffixIcon: IconButton(
                        key: const ValueKey('transferTake'),
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => _take(_input.text),
                      ),
                    ),
                    onSubmitted: _take,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Beide Handys sind danach dasselbe Konto. Das alte kannst du '
            'weiter nutzen oder die App dort löschen.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
