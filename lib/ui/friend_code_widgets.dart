import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/account.dart';

/// Shows the own friend code, as text and as QR code.
class MyFriendCode extends StatelessWidget {
  const MyFriendCode({super.key, required this.account});
  final Account account;

  void _showQr(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mein QR-Code'),
        content: SizedBox(
          width: 260,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: account.qrPayload,
                    size: 236,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Freund scannt diesen Code unter\n„Freund hinzufügen → QR scannen“.',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Dein Freundescode'),
        const SizedBox(height: 4),
        SelectableText(
          account.shortCode,
          key: const ValueKey('shortCode'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _showQr(context),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('QR-Code'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: account.shortCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Freundescode kopiert')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Kopieren'),
            ),
            OutlinedButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text:
                      'Spiel mit mir in Mobile Games! Mein Freundescode: '
                      '${account.shortCode}',
                ),
              ),
              icon: const Icon(Icons.share),
              label: const Text('Teilen'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Camera screen that returns the content of the first QR code it sees.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-Code scannen')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _done = true;
                  Navigator.pop(context, v);
                  return;
                }
              }
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kamera nicht verfügbar (${error.errorCode.name}).\n'
                  'Bitte den Zugriff auf die Kamera erlauben.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              'Halte die Kamera auf den QR-Code deines Freundes',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
