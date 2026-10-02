import 'dart:async';

import 'package:flutter/material.dart';

import 'core/chat.dart';
import 'core/net/matchmaker.dart';
import 'core/notifications.dart';
import 'core/services.dart';
import 'games/registry.dart';
import 'ui/friends_screen.dart';
import 'ui/home_screen.dart';
import 'ui/lobby_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.init();
  runApp(const MobileGamesApp());
}

class MobileGamesApp extends StatefulWidget {
  const MobileGamesApp({super.key});

  @override
  State<MobileGamesApp> createState() => _MobileGamesAppState();
}

class _MobileGamesAppState extends State<MobileGamesApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<IncomingInvite>? _invites;
  StreamSubscription<IncomingChat>? _chats;
  StreamSubscription<String>? _requests;
  StreamSubscription<String>? _accepts;

  @override
  void initState() {
    super.initState();
    if (Services.isReady) {
      _invites = Services.I.matchmaker.invites.listen(_onInvite);
      _chats = Services.I.chat.incoming.listen(_onChat);
      _requests = Services.I.friendRequests.incoming.listen(_onFriendRequest);
      _accepts = Services.I.friendRequests.accepted.listen(_onFriendAccepted);
      Notifications.I.onTap = (payload) {
        if (payload.startsWith('chat:')) _openChat(payload.substring(5));
        if (payload == 'friends') {
          _navigator.currentState?.push(
            MaterialPageRoute<void>(builder: (_) => const FriendsScreen()),
          );
        }
      };
    }
  }

  @override
  void dispose() {
    _invites?.cancel();
    _chats?.cancel();
    _requests?.cancel();
    _accepts?.cancel();
    super.dispose();
  }

  Future<void> _onFriendRequest(String pubkey) async {
    final fr = Services.I.friendRequests;
    final name = fr.pending[pubkey] ?? 'Jemand';
    if (!Notifications.I.inForeground) {
      Notifications.I.show(
        'Freundschaftsanfrage',
        '$name möchte mit dir befreundet sein.',
        payload: 'friends',
      );
    }
    final ctx = _navigator.currentContext;
    if (ctx == null) return;
    final accept = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.person_add, size: 40),
        title: const Text('Freundschaftsanfrage'),
        content: Text('$name möchte mit dir befreundet sein.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ablehnen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Annehmen'),
          ),
        ],
      ),
    );
    if (accept == true) await fr.acceptRequest(pubkey);
    if (accept == false) await fr.declineRequest(pubkey);
  }

  void _onFriendAccepted(String pubkey) {
    final name = Services.I.account.friend(pubkey)?.name ?? 'Jemand';
    if (!Notifications.I.inForeground) {
      Notifications.I.show('Neuer Freund', '$name ist jetzt dein Freund.');
      return;
    }
    _messenger.currentState?.showSnackBar(
      SnackBar(content: Text('🤝 $name ist jetzt dein Freund')),
    );
  }

  String _senderName(String pubkey, String? fallback) =>
      Services.I.account.friend(pubkey)?.name ?? fallback ?? 'Jemand';

  void _openChat(String pubkey) {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => FriendChatScreen(pubkey: pubkey)),
    );
  }

  void _onChat(IncomingChat c) {
    // Old messages fetched after a restart do not trigger popups.
    if (DateTime.now().difference(c.message.time) >
        const Duration(minutes: 10)) {
      return;
    }
    final name = _senderName(c.from, c.senderName);
    if (!Notifications.I.inForeground) {
      Notifications.I.show(name, c.message.text, payload: 'chat:${c.from}');
      return;
    }
    if (Services.I.chat.openConversation == c.from) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text('💬 $name: ${c.message.text}'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Öffnen',
          onPressed: () => _openChat(c.from),
        ),
      ),
    );
  }

  Future<void> _onInvite(IncomingInvite invite) async {
    final ctx = _navigator.currentContext;
    final game = gameById(invite.gameId);
    if (ctx == null || game == null) return;
    final mm = Services.I.matchmaker;
    if (!Notifications.I.inForeground) {
      Notifications.I.show(
        'Einladung zu ${game.title}',
        '${invite.fromName} möchte mit dir spielen – tippe zum Öffnen.',
        payload: 'invite',
      );
    }
    final dialogCtx = Completer<BuildContext>();
    final cancelled = mm.cancelledInvites
        .where((id) => id == invite.matchId)
        .first;
    cancelled
        .then((_) async {
          final c = await dialogCtx.future;
          if (c.mounted) Navigator.pop(c, null);
        })
        .catchError((_) {});
    final accept = await showDialog<bool>(
      context: ctx,
      builder: (c) {
        if (!dialogCtx.isCompleted) dialogCtx.complete(c);
        return AlertDialog(
          icon: Icon(game.icon, color: game.color, size: 40),
          title: Text('Einladung zu ${game.title}'),
          content: Text('${invite.fromName} möchte mit dir spielen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Ablehnen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Annehmen'),
            ),
          ],
        );
      },
    );
    if (accept == null) return; // withdrawn
    if (!accept) {
      mm.declineInvite(invite);
      return;
    }
    final match = await mm.acceptInvite(invite);
    final c = _navigator.currentContext;
    if (c == null || !c.mounted) return;
    if (match == null) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('Die Einladung ist nicht mehr gültig.')),
      );
    } else {
      openInvitedGame(c, match);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Games',
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
