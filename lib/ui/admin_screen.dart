import 'package:flutter/material.dart';

import '../core/leaderboard.dart';
import '../core/moderation.dart';
import '../core/moderation_sync.dart';
import '../core/nostr/keys.dart';
import '../core/services.dart';
import 'moderation_ui.dart';

/// Reports, the ban list and results to approve, for the admins only.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = Services.I.moderation;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderation'),
          bottom: TabBar(
            tabs: [
              ListenableBuilder(
                listenable: sync,
                builder: (_, _) =>
                    Tab(text: 'Meldungen (${sync.openReports.length})'),
              ),
              ListenableBuilder(
                listenable: Moderation.I,
                builder: (_, _) =>
                    Tab(text: 'Gesperrt (${Moderation.I.banned.length})'),
              ),
              const Tab(text: 'Bestwerte'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Reports(sync: sync),
            _Bans(sync: sync),
            _Approvals(sync: sync),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime t) =>
    '${t.day}.${t.month}.${t.year} '
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

class _Reports extends StatelessWidget {
  const _Reports({required this.sync});
  final ModerationSync sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sync, Moderation.I]),
      builder: (context, _) {
        final reports = sync.openReports;
        if (reports.isEmpty) {
          return const Center(child: Text('Keine offenen Meldungen.'));
        }
        // How often each player was reported.
        final counts = <String, int>{};
        for (final r in reports) {
          final k = r.pubkey;
          if (k != null) counts[k] = (counts[k] ?? 0) + 1;
        }
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            for (final r in reports)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.flag),
                  title: Text(
                    r.pubkey != null && counts[r.pubkey]! > 1
                        ? '${r.name} (${counts[r.pubkey]}× gemeldet)'
                        : r.name,
                  ),
                  subtitle: Text(
                    '${r.reason.isEmpty ? 'Ohne Begründung' : r.reason}\n'
                    'von ${r.fromName} • ${_date(r.time)}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.pubkey == null
                          ? 'ID unbekannt'
                          : 'ID ${shortCodeFor(r.pubkey!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    if (r.messages.isEmpty) const Text('Keine Nachrichten.'),
                    for (final m in r.messages) Text('> $m'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => sync.dismiss(r),
                          child: const Text('Erledigt'),
                        ),
                        if (r.pubkey != null) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: ValueKey('ban${r.id}'),
                            onPressed: () => banPlayer(
                              context,
                              pubkey: r.pubkey!,
                              name: r.name,
                            ),
                            icon: const Icon(Icons.gpp_bad),
                            label: const Text('Für alle sperren'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bans extends StatelessWidget {
  const _Bans({required this.sync});
  final ModerationSync sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sync, Moderation.I]),
      builder: (context, _) {
        final banned = Moderation.I.banned;
        if (banned.isEmpty) {
          return const Center(child: Text('Niemand ist gesperrt.'));
        }
        final mine = sync.myBans;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            for (final e in banned.entries)
              ListTile(
                leading: const Icon(Icons.gpp_bad),
                title: Text(e.value),
                subtitle: Text(
                  mine.containsKey(e.key)
                      ? 'ID ${shortCodeFor(e.key)}'
                      : 'ID ${shortCodeFor(e.key)} • von anderem Admin',
                ),
                trailing: mine.containsKey(e.key)
                    ? TextButton(
                        onPressed: () => banPlayer(
                          context,
                          pubkey: e.key,
                          name: e.value,
                          banned: false,
                        ),
                        child: const Text('Entsperren'),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Results on checked boards that come without a recorded game – e.g.
/// records from older app versions. Approved ones count from then on.
class _Approvals extends StatefulWidget {
  const _Approvals({required this.sync});
  final ModerationSync sync;

  @override
  State<_Approvals> createState() => _ApprovalsState();
}

class _ApprovalsState extends State<_Approvals> {
  List<RemoteScores>? _all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _all = null);
    final all = await Services.I.leaderboard.fetch();
    if (mounted) setState(() => _all = all);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    if (all == null) return const Center(child: CircularProgressIndicator());
    return ListenableBuilder(
      listenable: widget.sync,
      builder: (context, _) {
        final open = [
          for (final r in all)
            for (final MapEntry(key: board, :value) in r.unchecked.entries)
              if (boardOrNull(board) case final b?
                  when !Leaderboard.counts(
                    b,
                    ScoreEntry(value, DateTime(0)),
                    r.pubkey,
                  ))
                (r, b, value),
        ];
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Werte ohne nachspielbare Partie, z. B. Rekorde aus älteren '
                  'App-Versionen. Übernommene Werte (und schlechtere) zählen '
                  'danach für alle.',
                ),
              ),
              if (open.isEmpty) const ListTile(title: Text('Nichts offen.')),
              for (final (r, b, value) in open)
                ListTile(
                  key: ValueKey('approve-${r.pubkey}-${b.id}'),
                  leading: const Icon(Icons.history),
                  title: Text('${r.name} – ${b.title}'),
                  subtitle: Text(b.format(value)),
                  trailing: TextButton(
                    onPressed: () => widget.sync.approve(r.pubkey, b.id, value),
                    child: const Text('Übernehmen'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
