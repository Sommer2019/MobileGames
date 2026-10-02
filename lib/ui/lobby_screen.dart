import 'package:flutter/material.dart';

import '../core/net/matchmaker.dart';
import '../core/services.dart';
import '../games/registry.dart';
import 'friends_screen.dart';
import 'play_setup.dart';

/// Starts an online match: creates the session and opens the game.
void openOnlineGame(BuildContext context, MatchInfo match) {
  final game = gameById(match.gameId);
  if (game == null || !game.isMultiplayer) return;
  final session = Services.I.createSession(match);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => game.multiplayerBuilder!(PlaySetup.online(session)),
    ),
  );
}

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key, required this.game});
  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(game.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(game.icon, size: 72, color: game.color),
          const SizedBox(height: 8),
          Text(
            game.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          _Section('Online (Peer-to-Peer)'),
          _OptionTile(
            key: const ValueKey('randomButton'),
            icon: Icons.shuffle,
            title: 'Zufälliger Gegner',
            subtitle: 'Mit jemandem spielen, der gerade auch sucht',
            onTap: () => _findRandom(context),
          ),
          _OptionTile(
            icon: Icons.person_add_alt_1,
            title: 'Freund einladen',
            subtitle: 'Aus deiner Freundesliste',
            onTap: () => _inviteFriend(context),
          ),
          const SizedBox(height: 16),
          _Section('Offline'),
          for (final m in game.offlineModes)
            _OptionTile(
              icon: m.icon,
              title: m.label,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => game.multiplayerBuilder!(m.setup),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _findRandom(BuildContext context) async {
    final mm = Services.I.matchmaker;
    final future = mm.findRandom(game.id);
    final match = await showDialog<MatchInfo>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        future
            .then((m) {
              if (c.mounted) Navigator.pop(c, m);
            })
            .catchError((_) {});
        return AlertDialog(
          title: const Text('Suche Gegner …'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Sobald jemand anderes ebenfalls ein Spiel sucht, geht es los.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                mm.cancelRandom();
                Navigator.pop(c);
              },
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    );
    if (match != null && context.mounted) openOnlineGame(context, match);
  }

  Future<void> _inviteFriend(BuildContext context) async {
    final services = Services.I;
    final friend = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const FriendsScreen(pickMode: true)),
    );
    if (friend == null || !context.mounted) return;
    final f = services.account.friend(friend);
    final name = f?.name ?? 'Freund';
    final mm = services.matchmaker;
    String? matchId;
    final future = mm.inviteFriend(friend, name, game.id);
    // The match id is needed to cancel; it is the last invite we sent.
    final result = await showDialog<MatchInfo?>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        future.then((m) {
          if (c.mounted) Navigator.pop(c, m);
        });
        return AlertDialog(
          title: Text('Einladung an $name'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('Warte auf Antwort …'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                matchId = mm.lastInviteId;
                if (matchId != null) mm.cancelInvite(matchId!);
              },
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    if (result != null) {
      openOnlineGame(context, result);
    } else if (matchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name hat abgelehnt oder ist nicht online.')),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
