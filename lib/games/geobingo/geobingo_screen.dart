import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import '../geo/regions.dart';
import '../geo/source_picker.dart';
import '../geo/street_view.dart';
import 'geobingo_logic.dart';

class GeoBingoScreen extends StatefulWidget {
  const GeoBingoScreen({
    super.key,
    required this.setup,
    this.viewBuilder,
    this.huntController,
    this.sources,
  });
  final PlaySetup setup;

  /// Replace the street pictures, the marking and the sources with keys
  /// (tests).
  final Widget Function(StreetViewMode mode)? viewBuilder;
  final StreetViewController? huntController;
  final List<GeoSource>? sources;

  @override
  State<GeoBingoScreen> createState() => _GeoBingoScreenState();
}

class _GeoBingoScreenState extends State<GeoBingoScreen> {
  PlaySetup get setup => widget.setup;
  int get players => setup.players;
  int get me => setup.mySeat;
  bool get isHost => setup.isHost && !setup.spectator;
  bool get canAct => !setup.spectator;

  late final List<GeoSource> _sources = widget.sources ?? availableSources;
  late GeoBingoGame game = GeoBingoGame(
    players: players,
    sources: widget.sources ?? defaultSources,
  );
  StreamSubscription<RoomMessage>? _sub;
  Timer? _tick;

  final _termField = TextEditingController();
  late final _huntView = widget.huntController ?? StreetViewController();
  final _reviewView = StreetViewController();

  /// Hunt: the term being looked for.
  int _term = 0;
  bool _marking = false;

  /// Review: position in [GeoBingoGame.toRate].
  int _rateIndex = 0;

  @override
  void initState() {
    super.initState();
    _sub = setup.listen((m) {
      final e = m.data['e'];
      if (m.data['t'] != 'e' || e is! List || e.isEmpty) return;
      if (game.apply(List.from(e), m.seat)) _after(e);
    });
    if (isHost) _act(['cfg', _cfg()]);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _termField.dispose();
    if (widget.huntController == null) _huntView.dispose();
    _reviewView.dispose();
    super.dispose();
  }

  Map<String, dynamic> _cfg({
    int? minutes,
    List<GeoSource>? sources,
    List<String>? blocked,
  }) => {
    'min': minutes ?? game.minutes,
    'src': [for (final s in sources ?? game.sources) s.name],
    'blocked': blocked ?? game.blocked,
  };

  void _act(List e) {
    if (!canAct || !game.apply(e, me)) return;
    setup.send({'t': 'e', 'e': e});
    _after(e);
  }

  void _after(List e) {
    switch (e.first) {
      case 'start':
        _term = 0;
        Sound.play(Sfx.click);
      case 'review':
        _rateIndex = 0;
        Sound.play(Sfx.thud);
        if (canAct && game.toRate(me).isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _act(['rated']));
        }
        _showRated();
      case 'rated' || 'rate':
        _maybeEnd();
    }
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (!mounted) return;
    if (game.phase == GeoPhase.hunt) {
      if (isHost && game.timeLeft(_now()) == 0) _endHunt();
      setState(() {});
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void _endHunt() {
    if (!isHost || game.phase != GeoPhase.hunt) return;
    _act([
      'review',
      {
        for (final MapEntry(:key, :value) in game.finds.entries)
          '$key': {for (final f in value.entries) '${f.key}': f.value.toJson()},
      },
    ]);
  }

  void _maybeEnd({bool force = false}) {
    if (!isHost || game.phase != GeoPhase.review) return;
    if (force || game.allRated) _act(['end', game.currentScores()]);
  }

  // ------------------------------------------------------------- setup

  void _addTerm() {
    final t = GeoBingoGame.clean(_termField.text);
    if (t.isEmpty) return;
    _act(isHost ? ['term', t] : ['prop', t]);
    _termField.clear();
  }

  Future<void> _pickRegions() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RegionPicker(initial: game.blocked),
    );
    if (picked != null) _act(['cfg', _cfg(blocked: picked)]);
  }

  Widget _setup() {
    final theme = Theme.of(context);
    final sources = _sources;
    final mine = game.proposals.where((p) => p.$1 == me).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!streetViewSupported)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Auf diesem Gerät gibt es kein Street View. '
                'Spiel lieber am Handy, auf dem Mac oder im Browser mit.',
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text('Zeit: ${game.minutes} min'),
                subtitle: isHost
                    ? Slider(
                        key: const ValueKey('gbMinutes'),
                        value: game.minutes.toDouble(),
                        min: GeoBingoGame.minMinutes.toDouble(),
                        max: GeoBingoGame.maxMinutes.toDouble(),
                        divisions:
                            GeoBingoGame.maxMinutes - GeoBingoGame.minMinutes,
                        label: '${game.minutes} min',
                        onChanged: (v) =>
                            _act(['cfg', _cfg(minutes: v.round())]),
                      )
                    : null,
              ),
              SourcePicker(
                available: sources,
                selected: game.sources,
                onChanged: isHost
                    ? (s) => _act(['cfg', _cfg(sources: s)])
                    : null,
              ),
              ListTile(
                key: const ValueKey('gbRegions'),
                leading: const Icon(Icons.block),
                title: const Text('Gesperrte Regionen'),
                subtitle: Text(blockedLabel(game.blocked)),
                trailing: isHost ? const Icon(Icons.edit) : null,
                onTap: isHost ? _pickRegions : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Begriffe (${game.terms.length}/${GeoBingoGame.maxTerms})',
          style: theme.textTheme.titleMedium,
        ),
        if (game.terms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              isHost
                  ? 'Füge Begriffe hinzu, z. B. „Feuerwehrauto“.'
                  : 'Der Host legt die Begriffe fest – du kannst welche '
                        'vorschlagen.',
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < game.terms.length; i++)
              InputChip(
                key: ValueKey('gbTerm$i'),
                label: Text(game.terms[i]),
                onDeleted: isHost ? () => _act(['del', i]) : null,
              ),
          ],
        ),
        if (canAct) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('gbTermField'),
                  controller: _termField,
                  maxLength: GeoBingoGame.maxTermLength,
                  decoration: InputDecoration(
                    hintText: isHost
                        ? 'Begriff hinzufügen'
                        : 'Begriff vorschlagen',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _addTerm(),
                ),
              ),
              IconButton(
                key: const ValueKey('gbAddTerm'),
                icon: Icon(isHost ? Icons.add : Icons.lightbulb_outline),
                tooltip: isHost ? 'Hinzufügen' : 'Vorschlagen',
                onPressed: _addTerm,
              ),
            ],
          ),
        ],
        if (isHost && game.proposals.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Vorschläge', style: theme.textTheme.titleMedium),
          for (final (seat, t) in game.proposals)
            ListTile(
              dense: true,
              title: Text(t),
              subtitle: Text('von ${setup.seatName(seat)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('gbAcc-$t'),
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: 'Annehmen',
                    onPressed: () => _act(['acc', t]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    tooltip: 'Ablehnen',
                    onPressed: () => _act(['rej', t]),
                  ),
                ],
              ),
            ),
        ],
        if (!isHost && mine.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Deine Vorschläge (warten auf den Host)',
            style: theme.textTheme.titleSmall,
          ),
          for (final (_, t) in mine) Text('• $t'),
        ],
        const SizedBox(height: 16),
        if (isHost)
          FilledButton.icon(
            key: const ValueKey('gbStart'),
            onPressed: game.terms.isEmpty || sources.isEmpty
                ? null
                : () => _act(['start', _now()]),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Suche starten'),
          )
        else
          const Center(child: Text('Warte, bis der Host startet …')),
      ],
    );
  }

  // -------------------------------------------------------------- hunt

  Future<void> _mark() async {
    if (_marking || !canAct || game.timeLeft(_now()) == 0) return;
    setState(() => _marking = true);
    final (view, error) = await _huntView.mark();
    if (!mounted) return;
    setState(() => _marking = false);
    final messenger = ScaffoldMessenger.of(context);
    if (view == null) {
      messenger.showSnackBar(SnackBar(content: Text(error ?? 'Fehler')));
      return;
    }
    if (isBlocked(view.country, game.blocked)) {
      final name = countryByCode[view.country]?.name ?? view.country;
      messenger.showSnackBar(
        SnackBar(content: Text('$name ist gesperrt – such woanders!')),
      );
      return;
    }
    _act(['find', _term, view.toJson()]);
    Sound.play(Sfx.place);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('„${game.terms[_term]}“ markiert ✓'),
      ),
    );
    // On to the next term not found yet.
    final mineNow = game.finds[me] ?? {};
    for (var k = 1; k <= game.terms.length; k++) {
      final i = (_term + k) % game.terms.length;
      if (!mineNow.containsKey(i)) {
        setState(() => _term = i);
        break;
      }
    }
  }

  String _clock(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _view(StreetViewMode mode, StreetViewController c) =>
      widget.viewBuilder?.call(mode) ??
      StreetView(controller: c, sources: game.sources, mode: mode);

  Widget _hunt() {
    final left = game.timeLeft(_now());
    final mine = game.finds[me] ?? {};
    final progress = [
      for (var p = 0; p < players; p++)
        if (p != me || setup.spectator)
          '${setup.seatName(p)} ${game.finds[p]?.length ?? 0}',
    ].join(' · ');
    return Column(
      children: [
        TurnBanner(
          text: left == 0
              ? 'Zeit um – gleich wird bewertet'
              : '⏱ ${_clock(left)} · gefunden ${mine.length}/${game.terms.length}',
          highlight: left > 0,
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              for (var i = 0; i < game.terms.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('gbHuntTerm$i'),
                    avatar: mine.containsKey(i)
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    label: Text(game.terms[i]),
                    selected: _term == i,
                    onSelected: (_) => setState(() => _term = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _view(StreetViewMode.hunt, _huntView)),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('gbMark'),
                  onPressed: canAct && left > 0 && !_marking ? _mark : null,
                  icon: _marking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.push_pin),
                  label: Text(
                    mine.containsKey(_term)
                        ? '„${game.terms[_term]}“ neu markieren'
                        : '„${game.terms[_term]}“ markieren',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('gbEndHunt'),
                  onPressed: _endHunt,
                  child: const Text('Beenden'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(progress, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ review

  void _showRated() {
    final list = game.toRate(me);
    if (_rateIndex >= list.length) return;
    final (owner, term) = list[_rateIndex];
    final v = game.finds[owner]?[term];
    if (v != null) _reviewView.show(v);
  }

  void _goTo(int i) {
    setState(() => _rateIndex = i);
    _showRated();
  }

  Widget _review() {
    final list = game.toRate(me);
    final waiting = [
      for (var p = 0; p < players; p++)
        if (!game.doneRating.contains(p) && game.toRate(p).isNotEmpty)
          setup.seatName(p),
    ];
    if (list.isEmpty || game.doneRating.contains(me) || !canAct) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                list.isEmpty && canAct
                    ? 'Die anderen haben nichts gefunden, das du bewerten '
                          'könntest.'
                    : 'Danke fürs Bewerten!',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (waiting.isNotEmpty)
                Text('Es bewerten noch: ${waiting.join(', ')}'),
              if (isHost) ...[
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('gbEvaluate'),
                  onPressed: () => _maybeEnd(force: true),
                  child: const Text('Jetzt auswerten'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final (owner, term) = list[_rateIndex];
    final stars = game.ratingBy(me, owner, term);
    final rated = list.where((x) => game.ratingBy(me, x.$1, x.$2) != null);
    return Column(
      children: [
        TurnBanner(
          text: '„${game.terms[term]}“ von ${setup.seatName(owner)}',
          highlight: true,
        ),
        Expanded(child: _view(StreetViewMode.show, _reviewView)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Wie gut passt das zum Begriff?',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 1; s <= 5; s++)
              IconButton(
                key: ValueKey('gbStar$s'),
                iconSize: 36,
                icon: Icon(
                  stars != null && s <= stars ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () {
                  _act(['rate', owner, term, s]);
                  if (_rateIndex + 1 < list.length) _goTo(_rateIndex + 1);
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _rateIndex > 0 ? () => _goTo(_rateIndex - 1) : null,
              ),
              Text('${_rateIndex + 1}/${list.length}'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _rateIndex + 1 < list.length
                    ? () => _goTo(_rateIndex + 1)
                    : null,
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('gbRated'),
                onPressed: rated.length == list.length
                    ? () => _act(['rated'])
                    : null,
                child: const Text('Fertig bewertet'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- results

  Widget _results() {
    final order = [for (var p = 0; p < players; p++) p]
      ..sort((a, b) => game.scores[b].compareTo(game.scores[a]));
    final winners = game.winners();
    final theme = Theme.of(context);
    return Column(
      children: [
        TurnBanner(
          text: winners.length > 1
              ? 'Gleichstand! 🎉'
              : setup.seatName(winners.single) == 'Du'
              ? 'Du gewinnst Geobingo! 🏆'
              : '${setup.seatName(winners.single)} gewinnt Geobingo! 🏆',
          highlight: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final (rank, p) in order.indexed)
                Card(
                  child: ExpansionTile(
                    key: ValueKey('gbResult$p'),
                    leading: CircleAvatar(child: Text('${rank + 1}')),
                    title: Text(setup.seatName(p)),
                    trailing: Text(
                      '${game.scores[p].round()} P.',
                      style: theme.textTheme.titleMedium,
                    ),
                    children: [
                      for (var i = 0; i < game.terms.length; i++)
                        ListTile(
                          dense: true,
                          title: Text(game.terms[i]),
                          subtitle: Text(_findText(p, i)),
                          trailing: Text('${game.findPoints(p, i).round()}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        GameOverActions(
          setup: setup,
          winnerSeats: winners,
          rematchLabel: 'Neue Runde',
          onRematch: () {
            if (isHost) {
              _act(['new']);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Der Host startet die nächste Runde.'),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  String _findText(int p, int i) {
    final f = game.finds[p]?[i];
    if (f == null) return 'nicht gefunden';
    final avg = game.average(p, i);
    final where = countryByCode[f.country]?.name ?? 'irgendwo';
    return avg == null
        ? '$where · nicht bewertet'
        : '$where · ${avg.toStringAsFixed(1)} ★';
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: setup,
      title: 'Geobingo',
      child: switch (game.phase) {
        GeoPhase.setup => _setup(),
        GeoPhase.hunt => _hunt(),
        GeoPhase.review => _review(),
        GeoPhase.results => _results(),
      },
    );
  }
}

/// Blocks whole continents or single countries.
class _RegionPicker extends StatefulWidget {
  const _RegionPicker({required this.initial});
  final List<String> initial;

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  late final Set<String> _blocked = widget.initial.toSet();
  String _filter = '';

  void _toggle(String code) => setState(
    () => _blocked.contains(code) ? _blocked.remove(code) : _blocked.add(code),
  );

  @override
  Widget build(BuildContext context) {
    final f = _filter.toLowerCase();
    final list = countries
        .where((c) => f.isEmpty || c.name.toLowerCase().contains(f))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Regionen sperren',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton(
                  key: const ValueKey('gbRegionsDone'),
                  onPressed: () => Navigator.pop(context, _blocked.toList()),
                  child: const Text('Fertig'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              children: [
                const Text('Kontinente'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final MapEntry(:key, :value) in continents.entries)
                      FilterChip(
                        key: ValueKey('gbContinent$key'),
                        label: Text(value),
                        selected: _blocked.contains('c:$key'),
                        onSelected: (_) => _toggle('c:$key'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Land suchen',
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
                for (final c in list)
                  CheckboxListTile(
                    dense: true,
                    value:
                        _blocked.contains(c.code) ||
                        _blocked.contains('c:${c.continent}'),
                    title: Text(c.name),
                    subtitle: Text(continents[c.continent]!),
                    onChanged: _blocked.contains('c:${c.continent}')
                        ? null
                        : (_) => _toggle(c.code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
