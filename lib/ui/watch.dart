import 'package:flutter/material.dart';

import '../core/account.dart';
import '../core/mirror.dart';
import '../core/net/room.dart';
import '../core/net/spectate.dart';
import '../core/services.dart';
import '../games/labyrinth/labyrinth_screen.dart';
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
    final watched = await connectToFriendGame(
      messenger: s.messenger,
      sessionFactory: s.createSession,
      friend: friend,
    );
    if (cancelled) {
      if (watched is GameRoom) await watched.close();
      if (watched is MirrorFeed) await watched.close();
      return;
    }
    nav.pop();
    if (watched is MirrorFeed) {
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => MirrorWatchScreen(feed: watched),
        ),
      );
      await watched.close();
      return;
    }
    final room = watched as GameRoom;
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

/// A friend's game that is played on their device (alone, against the
/// computer or with people at that device), shown live without input.
class MirrorWatchScreen extends StatelessWidget {
  const MirrorWatchScreen({super.key, required this.feed});
  final MirrorFeed feed;

  Widget _game() {
    // The labyrinth is watched inside a level, not in the level list.
    if (feed.gameId == 'labyrinth') {
      return LabyrinthScreen(levelIndex: feed.setup['level'] as int? ?? 0);
    }
    final game = gameById(feed.gameId);
    if (game == null) return const SizedBox();
    final multi = game.multiplayerBuilder;
    if (feed.setup.containsKey('players') && multi != null) {
      return multi(PlaySetup.mirror(feed.setup));
    }
    final single = game.singleplayerBuilder;
    if (single != null) return single();
    return multi != null
        ? multi(PlaySetup.mirror(feed.setup))
        : const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MirrorScope(
      feed: feed,
      child: Stack(
        children: [
          Positioned.fill(child: AbsorbPointer(child: _game())),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(24),
                color: scheme.inverseSurface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: feed.ended,
                          builder: (context, ended, _) => Text(
                            ended
                                ? '${feed.friendName} hat das Spiel verlassen'
                                : '👁 Du schaust ${feed.friendName} zu',
                            style: TextStyle(color: scheme.onInverseSurface),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('mirrorClose'),
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.maybePop(context),
                        icon: Icon(Icons.close, color: scheme.onInverseSurface),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
