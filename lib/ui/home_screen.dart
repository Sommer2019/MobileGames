import 'package:flutter/material.dart';

import '../core/home_widgets.dart';
import '../core/konami.dart';
import '../core/secrets.dart';
import '../core/services.dart';
import '../core/sound.dart';
import '../games/registry.dart';
import '../games/tournament/tournament_screen.dart';
import 'friends_screen.dart';
import 'fuzzy.dart';
import 'leaderboard_screen.dart';
import 'lobby_screen.dart';
import 'rules_sheet.dart';
import 'secrets_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Only this category (null: all).
  GameCategory? _category;

  /// Only games for one person (also against computers), or only games
  /// with others (null: both).
  bool? _alone;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(GameInfo g) {
    if (_category != null && g.category != _category) return false;
    if (_alone == true && !g.playableAlone) return false;
    if (_alone == false && !g.isMultiplayer) return false;
    final q = _query.trim();
    if (q.isEmpty) return true;
    return fuzzyMatch(
      q,
      '${g.title} ${g.description} ${g.category.label} '
      '${g.isMultiplayer ? 'mehrspieler online' : ''} '
      '${g.playableAlone ? 'allein einzelspieler computer' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = games.where(_matches).toList();
    final searching = _query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Games'),
        actions: [
          ListenableBuilder(
            listenable: Secrets.I,
            builder: (context, _) =>
                Secrets.I.unlocked || Secrets.I.arenaUnlocked
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
        onArena: () async {
          await Secrets.I.unlockArena();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '🤖 Bot-Arena freigeschaltet! Bei „Spieler & Computer '
                'wählen“ dürfen jetzt alle Plätze Computer sein.',
              ),
            ),
          );
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
            SliverToBoxAdapter(child: _filters(context)),
            if (shown.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Kein Spiel gefunden 🤷')),
                ),
              )
            else if (searching || _category != null || _alone != null)
              _grid(context, shown)
            else
              for (final c in GameCategory.values)
                if (shown.any((g) => g.category == c)) ...[
                  _header(context, c),
                  _grid(context, [
                    for (final g in shown)
                      if (g.category == c) g,
                  ]),
                ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('gameSearch'),
          controller: _search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Spiel suchen',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Leeren',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                key: const ValueKey('category-all'),
                label: const Text('Alle'),
                selected: _category == null && _alone == null,
                onSelected: (_) => setState(() {
                  _category = null;
                  _alone = null;
                }),
              ),
              for (final (alone, label, icon) in [
                (true, 'Allein', Icons.person),
                (false, 'Mehrspieler', Icons.people),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    key: ValueKey(alone ? 'filter-alone' : 'filter-multi'),
                    avatar: Icon(icon, size: 18),
                    label: Text(label),
                    selected: _alone == alone,
                    onSelected: (_) =>
                        setState(() => _alone = _alone == alone ? null : alone),
                  ),
                ),
              const SizedBox(height: 24, child: VerticalDivider(width: 16)),
              for (final c in GameCategory.values)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    key: ValueKey('category-${c.name}'),
                    avatar: Icon(c.icon, size: 18),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) =>
                        setState(() => _category = _category == c ? null : c),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _header(BuildContext context, GameCategory c) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(c.icon),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              c.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
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
      child: Stack(
        children: [
          Positioned.fill(child: _tile(context)),
          Positioned(
            top: 0,
            right: 0,
            child: RulesButton(game: game, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context) {
    return InkWell(
      key: ValueKey('game-${game.id}'),
      onTap: () {
        HomeWidgets.recordPlayed(game.id);
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => game.isMultiplayer
                ? LobbyScreen(game: game)
                : game.singleplayerBuilder!(),
          ),
        );
      },
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(game.icon, size: 40, color: Colors.white),
                const SizedBox(width: 6),
                // How it can be played: with others, alone.
                if (game.isMultiplayer)
                  const Icon(Icons.people, size: 16, color: Colors.white70),
                if (game.playableAlone)
                  const Icon(Icons.person, size: 16, color: Colors.white70),
              ],
            ),
            const Spacer(),
            // Long titles shrink to one line.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                game.title,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
    );
  }
}
