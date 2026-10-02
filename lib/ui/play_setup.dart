import 'dart:async';

import 'package:flutter/material.dart';

import '../core/net/room.dart';
import 'chat_view.dart';

enum PlayKind { local, ai, online }

/// How a game is played: on one device, against the computer or online.
class PlaySetup {
  const PlaySetup.local({int players = 2})
    : kind = PlayKind.local,
      _players = players,
      room = null;
  const PlaySetup.ai() : kind = PlayKind.ai, _players = 2, room = null;
  const PlaySetup.online(GameRoom this.room)
    : kind = PlayKind.online,
      _players = 0;

  final PlayKind kind;
  final int _players;
  final GameRoom? room;

  bool get online => kind == PlayKind.online;

  /// Number of players taking part.
  int get players => room?.size ?? _players;

  /// Seat of this device online (0 = host). Offline always 0.
  int get mySeat => room?.mySeat ?? 0;

  /// The host plays first / white.
  bool get isHost => mySeat == 0;

  /// For two player games: the other player's name.
  String get opponentName {
    final r = room;
    if (r == null) return 'Gegner';
    return r.names[r.mySeat == 0 ? 1 : 0];
  }

  /// Sends a game message to the other players (no-op offline).
  void send(Map<String, dynamic> data) => room?.send(data);

  /// Game messages of the other players.
  StreamSubscription<RoomMessage>? listen(void Function(RoomMessage) onData) =>
      room?.messages.listen(onData);
}

/// Wraps a game screen: online it shows the connection type, offers the
/// in-game chat, handles players leaving and closes the room on exit.
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
  StreamSubscription<ChatLine>? _chatSub;
  bool _leftDialogShown = false;
  bool _chatOpen = false;
  int _unread = 0;

  GameRoom? get _room => widget.setup.room;

  @override
  void initState() {
    super.initState();
    final r = _room;
    if (r != null) {
      r.addListener(_onRoomChanged);
      _chatSub = r.chatStream.listen((line) {
        if (!mounted || line.seat == r.mySeat) return;
        if (!_chatOpen) {
          setState(() => _unread++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${line.name}: ${line.text}'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(label: 'Chat', onPressed: _openChat),
            ),
          );
        }
      });
    }
  }

  void _onRoomChanged() {
    if (!mounted) return;
    setState(() {});
    final left = _room?.leftPlayer;
    if (left != null && !_leftDialogShown) {
      _leftDialogShown = true;
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Spiel beendet'),
          content: Text('$left hat das Spiel verlassen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _room?.removeListener(_onRoomChanged);
    _room?.close();
    super.dispose();
  }

  Future<void> _openChat() async {
    final r = _room;
    if (r == null) return;
    setState(() {
      _chatOpen = true;
      _unread = 0;
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.6,
          child: ListenableBuilder(
            listenable: r,
            builder: (context, _) => ChatView(
              lines: [
                for (final l in r.chat)
                  ChatEntry(
                    mine: l.seat == r.mySeat,
                    author: l.name,
                    text: l.text,
                    time: l.time,
                  ),
              ],
              onSend: r.sendChat,
              quickReplies: const [
                'Gutes Spiel!',
                'Nochmal?',
                'Glückwunsch! 🎉',
                'Oh nein 😅',
                'Moment …',
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _chatOpen = false);
  }

  Future<bool> _confirmLeave() async {
    final r = _room;
    if (r == null || r.leftPlayer != null) return true;
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
    final r = _room;
    return PopScope(
      canPop: r == null || r.leftPlayer != null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (r != null) _ConnectionChip(room: r),
            if (r != null)
              IconButton(
                tooltip: 'Chat',
                onPressed: _openChat,
                icon: Badge(
                  isLabelVisible: _unread > 0,
                  label: Text('$_unread'),
                  child: const Icon(Icons.chat_bubble_outline),
                ),
              ),
            ...?widget.actions,
          ],
        ),
        body: SafeArea(
          child: Center(
            // Keeps boards at a pleasant size on tablets.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.room});
  final GameRoom room;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = room.leftPlayer != null
        ? ('Getrennt', Icons.link_off, Colors.red)
        : room.isDirect
        ? ('P2P', Icons.bolt, Colors.green)
        : ('Relay', Icons.cloud_sync, Colors.blueGrey);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: room.isDirect
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

/// Full screen cover for pass-and-play games, so the next player does not
/// see the previous player's secret information.
class PassDeviceCover extends StatelessWidget {
  const PassDeviceCover({
    super.key,
    required this.playerName,
    required this.onReady,
  });
  final String playerName;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_android, size: 64),
            const SizedBox(height: 16),
            Text(
              'Gerät an $playerName übergeben',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onReady,
              child: const Text('Ich bin bereit'),
            ),
          ],
        ),
      ),
    );
  }
}
