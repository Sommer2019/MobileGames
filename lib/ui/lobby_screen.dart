import 'package:flutter/material.dart';

import '../core/net/matchmaker.dart';
import '../games/registry.dart';
import 'room_screens.dart';

/// Opens the waiting screen after accepting an invite.
void openInvitedGame(BuildContext context, MatchInfo match) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GuestWaitScreen(match: match)),
  );
}

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key, required this.game});
  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    final multi = game.maxOnlinePlayers > 2;
    return Scaffold(
      appBar: AppBar(title: Text(game.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
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
              const _Section('Online (Peer-to-Peer)'),
              _OptionTile(
                key: const ValueKey('randomButton'),
                icon: Icons.shuffle,
                title: multi ? 'Zufällige Gegner' : 'Zufälliger Gegner',
                subtitle: multi
                    ? '2 bis ${game.maxOnlinePlayers} Spieler'
                    : 'Mit jemandem spielen, der gerade auch sucht',
                onTap: () => _random(context),
              ),
              _OptionTile(
                icon: Icons.group_add,
                title: 'Mit Freunden spielen',
                subtitle: multi
                    ? 'Bis zu ${game.maxOnlinePlayers - 1} Freunde einladen'
                    : 'Einen Freund einladen',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => FriendsRoomScreen(game: game),
                  ),
                ),
              ),
              if (game.offlineModes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Section('Offline'),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _random(BuildContext context) async {
    var size = 2;
    if (game.maxOnlinePlayers > 2) {
      final chosen = await showDialog<int>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Wie viele Spieler?'),
          children: [
            for (var n = 2; n <= game.maxOnlinePlayers; n++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, n),
                child: Text('$n Spieler', style: const TextStyle(fontSize: 18)),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      size = chosen;
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RandomMatchScreen(game: game, size: size),
      ),
    );
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
