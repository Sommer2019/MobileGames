import 'package:flutter/material.dart';

import '../core/konami.dart';
import '../core/secrets.dart';
import '../core/services.dart';
import '../core/sound.dart';
import '../games/registry.dart';
import '../games/tournament/tournament_screen.dart';
import 'friends_screen.dart';
import 'leaderboard_screen.dart';
import 'lobby_screen.dart';
import 'secrets_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final multi = games.where((g) => g.isMultiplayer).toList();
    final single = games
        .where((g) => !g.isMultiplayer || g.alsoSingleplayer)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Games'),
        actions: [
          ListenableBuilder(
            listenable: Secrets.I,
            builder: (context, _) => Secrets.I.unlocked
                ? IconButton(
                    key: const ValueKey('secretsButton'),
                    tooltip: 'Geheimnisse',
                    icon: const Text('🎮', style: TextStyle(fontSize: 20)),
                    onPressed: () => showSecretsSheet(context),
                  )
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: Sound.enabled,
            builder: (context, on, _) => IconButton(
              key: const ValueKey('soundToggle'),
              tooltip: on ? 'Ton aus' : 'Ton an',
              icon: Icon(on ? Icons.volume_up : Icons.volume_off),
              onPressed: () => Sound.setEnabled(!on),
            ),
          ),
          IconButton(
            tooltip: 'Bestenliste',
            icon: const Icon(Icons.leaderboard),
            onPressed: () => openLeaderboard(context),
          ),
          if (Services.isReady)
            ListenableBuilder(
              listenable: Listenable.merge([
                Services.I.account,
                Services.I.chat,
              ]),
              builder: (context, _) => TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const FriendsScreen(),
                  ),
                ),
                icon: Badge(
                  isLabelVisible:
                      Services.I.chat.totalUnread +
                          Services.I.friendRequests.pending.length >
                      0,
                  label: Text(
                    '${Services.I.chat.totalUnread + Services.I.friendRequests.pending.length}',
                  ),
                  child: const Icon(Icons.people),
                ),
                label: Text(
                  Services.I.account.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
      body: KonamiDetector(
        onUnlocked: () async {
          await Secrets.I.unlock();
          if (context.mounted) await showSecretsSheet(context);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  color: const Color(0xFFFFF3C4),
                  child: ListTile(
                    key: const ValueKey('tournamentCard'),
                    leading: const Icon(
                      Icons.emoji_events,
                      size: 40,
                      color: Color(0xFFF9A825),
                    ),
                    title: const Text(
                      'Turnier mit Freunden',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: const Text(
                      'Mehrere Spiele, mehrere Runden, eine Tabelle',
                      style: TextStyle(color: Colors.black54),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.black54,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const TournamentSetupScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _header(
              context,
              'Mehrspieler',
              'Online gegen Freunde oder zufällige Gegner – oder offline',
            ),
            _grid(context, multi),
            _header(context, 'Einzelspieler', null),
            _grid(context, single),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title, String? subtitle) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null)
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );

  Widget _grid(BuildContext context, List<GameInfo> list) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    sliver: SliverGrid.extent(
      maxCrossAxisExtent: 220,
      childAspectRatio: 1.05,
      children: [for (final g in list) _GameCard(game: g)],
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});
  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('game-${game.id}'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => game.isMultiplayer
                ? LobbyScreen(game: game)
                : game.singleplayerBuilder!(),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [game.color, Color.lerp(game.color, Colors.black, 0.35)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(game.icon, size: 40, color: Colors.white),
              const Spacer(),
              Text(
                game.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                game.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
