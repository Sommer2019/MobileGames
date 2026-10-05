import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/net/spectate.dart';
import '../core/services.dart';
import '../games/registry.dart';
import 'play_setup.dart';

/// Title of a game for "spielt …".
String gameTitle(String id) => gameById(id)?.title ?? id;

/// Connects to [friend]'s game and opens it as a spectator.
Future<void> watchFriendGame(BuildContext context, Friend friend) async {
  final s = Services.I;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  var cancelled = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text('Verbinde mit ${friend.name} …')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.pop(c);
          },
          child: const Text('Abbrechen'),
        ),
      ],
    ),
  );
  try {
    final room = await watchFriend(
      messenger: s.messenger,
      sessionFactory: s.createSession,
      friend: friend,
    );
    if (cancelled) {
      await room.close();
      return;
    }
    nav.pop();
    final game = gameById(room.gameId);
    final builder = game?.multiplayerBuilder;
    if (builder == null) {
      await room.close();
      return;
    }
    await nav.push(
      MaterialPageRoute<void>(builder: (_) => builder(PlaySetup.online(room))),
    );
  } catch (e) {
    if (cancelled) return;
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
