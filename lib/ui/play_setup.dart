import 'dart:async';

import 'package:flutter/material.dart';

import '../core/net/game_session.dart';

enum PlayKind { local, ai, online }

/// How a game is played: on one device, against the computer or online.
class PlaySetup {
  const PlaySetup.local({this.players = 2})
    : kind = PlayKind.local,
      session = null;
  const PlaySetup.ai() : kind = PlayKind.ai, players = 2, session = null;
  const PlaySetup.online(GameSession this.session)
    : kind = PlayKind.online,
      players = 2;

  final PlayKind kind;
  final int players;
  final GameSession? session;

  bool get online => kind == PlayKind.online;

  /// The host plays first / white.
  bool get isHost => session?.match.isHost ?? true;
  String get opponentName => session?.match.opponentName ?? 'Gegner';
}

/// Wraps an online game: shows the connection state, handles the opponent
/// leaving and closes the session when the screen is left.
class OnlineGameFrame extends StatefulWidget {
  const OnlineGameFrame({
    super.key,
    required this.setup,
    required this.title,
    required this.child,
    this.actions,
  });

  final PlaySetup setup;
  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  State<OnlineGameFrame> createState() => _OnlineGameFrameState();
}

class _OnlineGameFrameState extends State<OnlineGameFrame> {
  StreamSubscription<LinkState>? _sub;
  bool _leftDialogShown = false;

  GameSession? get _session => widget.setup.session;

  @override
  void initState() {
    super.initState();
    final s = _session;
    if (s != null) {
      _sub = s.stateChanges.listen((state) {
        if (!mounted) return;
        setState(() {});
        if (state == LinkState.opponentLeft && !_leftDialogShown) {
          _leftDialogShown = true;
          showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Spiel beendet'),
              content: Text(
                '${widget.setup.opponentName} hat das Spiel verlassen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      });
      s.start();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session?.close();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    final s = _session;
    if (s == null || s.state == LinkState.opponentLeft) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Spiel verlassen?'),
        content: const Text('Das laufende Online-Spiel wird beendet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Bleiben'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Verlassen'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return PopScope(
      canPop: s == null || s.state == LinkState.opponentLeft,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (s != null) _ConnectionChip(session: s),
            ...?widget.actions,
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (s != null && s.state == LinkState.connecting)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'Verbinde mit ${widget.setup.opponentName} …',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (session.state) {
      LinkState.connecting => ('Verbinde', Icons.sync, Colors.orange),
      LinkState.opponentLeft => ('Getrennt', Icons.link_off, Colors.red),
      LinkState.connected =>
        session.isDirect
            ? ('P2P', Icons.bolt, Colors.green)
            : ('Relay', Icons.cloud_sync, Colors.blueGrey),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: session.isDirect
            ? 'Direkte Peer-to-Peer-Verbindung'
            : 'Verschlüsselt über öffentliche Relays (P2P wird versucht)',
        child: Chip(
          avatar: Icon(icon, size: 16, color: color),
          label: Text(label),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// Banner showing whose turn it is.
class TurnBanner extends StatelessWidget {
  const TurnBanner({
    super.key,
    required this.text,
    this.highlight = false,
    this.color,
  });
  final String text;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: highlight
            ? (color ?? scheme.primaryContainer)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
