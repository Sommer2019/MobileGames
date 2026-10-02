import 'dart:async';

import 'package:flutter/material.dart';

import 'core/net/matchmaker.dart';
import 'core/services.dart';
import 'games/registry.dart';
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
  StreamSubscription<IncomingInvite>? _invites;

  @override
  void initState() {
    super.initState();
    if (Services.isReady) {
      _invites = Services.I.matchmaker.invites.listen(_onInvite);
    }
  }

  @override
  void dispose() {
    _invites?.cancel();
    super.dispose();
  }

  Future<void> _onInvite(IncomingInvite invite) async {
    final ctx = _navigator.currentContext;
    final game = gameById(invite.gameId);
    if (ctx == null || game == null) return;
    final mm = Services.I.matchmaker;
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
      ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('Die Einladung ist nicht mehr gültig.')),
      );
    } else {
      openOnlineGame(c, match);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Games',
      navigatorKey: _navigator,
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
