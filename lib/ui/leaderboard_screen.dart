import 'package:flutter/material.dart';

import '../core/leaderboard.dart';
import '../core/services.dart';

/// Opens the leaderboard, preselecting the first board of [game].
void openLeaderboard(BuildContext context, {String? game}) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(game: game)),
  );
}

/// App-bar button for single player games.
class LeaderboardButton extends StatelessWidget {
  const LeaderboardButton({super.key, required this.game});
  final String game;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Bestenliste',
    icon: const Icon(Icons.leaderboard),
    onPressed: () => openLeaderboard(context, game: game),
  );
}

/// Rankings for the single player games: own results, friends and everybody.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, this.game});
  final String? game;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late ScoreBoard board = visibleBoards().firstWhere(
    (b) => b.game == widget.game,
    orElse: () => visibleBoards().first,
  );
  List<ScoreEntry> mine = [];
  List<RemoteScores>? everyone;
  List<RemoteScores>? friends;
  bool loading = false;

  bool get online => Services.isReady;

  @override
  void initState() {
    super.initState();
    _loadMine();
    _loadRemote();
  }

  Future<void> _loadMine() async {
    final h = await Leaderboard.history(board.id);
    if (mounted) setState(() => mine = h);
  }

  Future<void> _loadRemote() async {
    if (!online || loading) return;
    final s = Services.I;
    setState(() => loading = true);
    await s.leaderboard.publish();
    final friendKeys = [
      s.account.keys.publicKey,
      for (final f in s.account.friends) f.pubkey,
    ];
    final results = await Future.wait([
      s.leaderboard.fetch(),
      s.leaderboard.fetch(authors: friendKeys),
    ]);
    if (!mounted) return;
    setState(() {
      loading = false;
      // Merge: the friends query may find entries the global one missed.
      final all = {for (final r in results[0]) r.pubkey: r};
      for (final r in results[1]) {
        all[r.pubkey] = r;
      }
      everyone = all.values.toList();
      friends = [
        for (final r in all.values)
          if (friendKeys.contains(r.pubkey)) r,
      ];
    });
  }

  void _select(ScoreBoard b) {
    setState(() {
      board = b;
      mine = [];
    });
    _loadMine();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bestenliste'),
          actions: [
            if (online)
              IconButton(
                tooltip: 'Aktualisieren',
                onPressed: loading ? null : _loadRemote,
                icon: const Icon(Icons.refresh),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(104),
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final b in visibleBoards())
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: ChoiceChip(
                            key: ValueKey('board-${b.id}'),
                            label: Text(b.title),
                            selected: b == board,
                            onSelected: (_) => _select(b),
                          ),
                        ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Ich'),
                    Tab(text: 'Freunde'),
                    Tab(text: 'Weltweit'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _mine(),
            _remote(friends, friendsTab: true),
            _remote(everyone, friendsTab: false),
          ],
        ),
      ),
    );
  }

  String get _hint =>
      board.lowerIsBetter ? 'Weniger ist besser.' : 'Mehr ist besser.';

  Widget _mine() {
    if (mine.isEmpty) {
      return _empty('Noch kein Ergebnis in „${board.title}“. $_hint');
    }
    return ListView(
      children: [
        _header(),
        for (var i = 0; i < mine.length; i++)
          _row(
            i,
            mine[i].at.millisecondsSinceEpoch == 0
                ? 'früherer Rekord'
                : _date(mine[i].at),
            mine[i].value,
          ),
      ],
    );
  }

  Widget _remote(List<RemoteScores>? list, {required bool friendsTab}) {
    if (!online) return _empty('Keine Verbindung.');
    if (list == null) return const Center(child: CircularProgressIndicator());
    final ranked = Leaderboard.rank(board, list);
    if (ranked.isEmpty) {
      return _empty(
        friendsTab
            ? 'Noch keine Ergebnisse von dir oder deinen Freunden.'
            : 'Noch keine Ergebnisse.',
      );
    }
    final me = Services.I.account.keys.publicKey;
    final names = {
      for (final f in Services.I.account.friends) f.pubkey: f.name,
    };
    return ListView(
      children: [
        _header(
          extra: friendsTab
              ? null
              : 'Ergebnisse werden nicht geprüft – jeder veröffentlicht '
                    'seine eigenen Bestwerte.',
        ),
        for (var i = 0; i < ranked.length && i < 100; i++)
          _row(
            i,
            (ranked[i].$1.pubkey == me
                    ? 'Du'
                    : names[ranked[i].$1.pubkey] ?? ranked[i].$1.name) +
                (ranked[i].$1.badge ? ' 🎮' : ''),
            ranked[i].$2,
            highlight: ranked[i].$1.pubkey == me,
          ),
      ],
    );
  }

  Widget _header({String? extra}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      '${board.title} – $_hint${extra == null ? '' : '\n$extra'}',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );

  Widget _row(int i, String name, int value, {bool highlight = false}) {
    final theme = Theme.of(context);
    return ListTile(
      tileColor: highlight ? theme.colorScheme.primaryContainer : null,
      leading: SizedBox(
        width: 36,
        child: Center(
          child: Text(
            i < 3 ? const ['🥇', '🥈', '🥉'][i] : '${i + 1}.',
            style: TextStyle(fontSize: i < 3 ? 24 : 16),
          ),
        ),
      ),
      title: Text(name, overflow: TextOverflow.ellipsis),
      trailing: Text(
        board.format(value),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
