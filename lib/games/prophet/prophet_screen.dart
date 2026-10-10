import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/mirror.dart';
import '../../core/net/room.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/bot_speed.dart';
import '../../ui/bot_turns.dart';
import '../../ui/play_setup.dart';
import 'prophet_logic.dart';

const prophetColors = [
  Color(0xFF1E88E5), // Blau
  Color(0xFFE53935), // Rot
  Color(0xFF43A047), // Grün
  Color(0xFFFBC02D), // Gelb
];
const prophetColorNames = ['Blau', 'Rot', 'Grün', 'Gelb'];

class ProphetScreen extends StatefulWidget {
  const ProphetScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<ProphetScreen> createState() => _ProphetScreenState();
}

class _ProphetScreenState extends State<ProphetScreen>
    with SavedGameState, GameMirror, SavedGameMirror, BotTurns {
  @override
  String? get mirrorGame => setup.online ? null : 'prophet';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  late int round = widget.setup.firstRound;
  late ProphetGame game = ProphetGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();
  Timer? _nextRound;

  /// Local seat whose hand is shown (pass and play with several humans).
  int? _viewer;

  /// Stars for exact predictions (secret).
  bool _stars = false;

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  bool get _canDeal => setup.runsGame;

  @override
  String? get saveKey => setup.saveKey('prophet');

  @override
  Map<String, dynamic>? saveGame() {
    if (!savingForMirror && (game.isOver || !game.dealt)) return null;
    return {'round': round, 'events': game.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = ProphetGame.replay(players, data['events'] as List, first: round);
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    if (!restoredGame && _canDeal) _deal();
    _viewer = _defaultViewer();
    _scheduleNextRound();
    scheduleBot();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nextRound?.cancel();
    super.dispose();
  }

  int? _defaultViewer() {
    // Spectators look over their friend's shoulder.
    if (setup.online) return setup.mySeat;
    final humans = [
      for (var p = 0; p < players; p++)
        if (!setup.isBot(p)) p,
    ];
    // Only computers (Bot-Arena): nobody's hand is shown.
    if (humans.isEmpty) return null;
    if (humans.length == 1) return humans.single;
    final c = game.toMove;
    return c != null && !setup.isBot(c) ? c : humans.first;
  }

  bool get _needsHandover {
    if (setup.online || setup.spectator) return false;
    final c = game.toMove;
    return c != null && !setup.isBot(c) && c != _viewer;
  }

  @override
  int? get seatToMove => game.toMove;

  /// A full trick stays a moment on the table before the next card.
  @override
  Duration get botDelay => game.trick.length == players
      ? const Duration(milliseconds: 1400)
      : const Duration(milliseconds: 800);

  @override
  void botAct(int seat) => _act(ProphetAi(_random).choose(game), seat);

  void _deal() => _act(['deal', _random.nextInt(1 << 30)], 0);

  void _act(List event, int seat) {
    if (!game.apply(event)) return;
    setup.sendAs(seat, {'t': 'e', 'e': event});
    _after(event);
  }

  void _after(List event) {
    setState(() {});
    switch (event.first) {
      case 'deal':
        if (!setup.online) _viewer = _defaultViewer();
        _stars = false;
        Sound.play(Sfx.card);
      case 'play':
        final full = game.trick.length == players;
        Sound.play(full ? Sfx.thud : Sfx.card);
      case 'bid' || 'trump':
        Sound.play(Sfx.click);
    }
    if (game.phase == ProphetPhase.roundOver ||
        game.phase == ProphetPhase.over) {
      _stars = Secrets.on(Secret.crystalBall) && game.exact.isNotEmpty;
    }
    persistGame();
    _scheduleNextRound();
    scheduleBot();
  }

  /// The device running the game deals the next round after a pause (or
  /// at once with "Weiter").
  void _scheduleNextRound() {
    if (!_canDeal || game.phase != ProphetPhase.roundOver) return;
    _nextRound?.cancel();
    _nextRound = Timer(BotSpeed.ms(6000), () {
      if (mounted && game.phase == ProphetPhase.roundOver) _deal();
    });
  }

  void _onMessage(RoomMessage m) {
    final d = m.data;
    switch (d['t']) {
      case 'e':
        final e = d['e'];
        if (e is! List || e.isEmpty) return;
        if (e.first == 'deal' ? m.seat != 0 : m.seat != game.current) return;
        if (game.apply(List.from(e))) _after(e);
      case 'again':
        if (_canDeal && (!game.dealt || game.isOver)) _again();
    }
  }

  void _again() {
    if (_canDeal) {
      if (!setup.online) round++;
      game = ProphetGame(players: players, first: round);
      _deal();
    } else {
      setup.send({'t': 'again'});
    }
  }

  bool get _myTurn {
    final c = game.toMove;
    return c != null && setup.humanControls(c) && !_needsHandover;
  }

  String _name(int seat) => setup.seatName(seat);

  String _status() {
    switch (game.phase) {
      case ProphetPhase.waiting:
        return 'Warte auf das Austeilen …';
      case ProphetPhase.over:
        final w = game.winners();
        if (w.length > 1) return 'Unentschieden!';
        final n = _name(w.single);
        return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
      case ProphetPhase.roundOver:
        return 'Runde ${game.cardsThisRound} vorbei';
      case _:
    }
    final c = game.current;
    final n = _name(c);
    final who = n == 'Du' ? 'Du bist dran' : '$n ist dran';
    if (!setup.humanControls(c) || setup.isBot(c)) {
      return switch (game.phase) {
        ProphetPhase.trumpChoice => '$n wählt Trumpf …',
        ProphetPhase.bidding => '$n sagt an …',
        _ => '$n ist dran …',
      };
    }
    return switch (game.phase) {
      ProphetPhase.trumpChoice => '$who – wähle Trumpf',
      ProphetPhase.bidding => '$who – wie viele Stiche machst du?',
      _ => who,
    };
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    final hand = viewer == null || !game.dealt
        ? <int>[]
        : (List.of(game.hands[viewer])..sort(_handOrder));
    final mine = _myTurn && viewer == game.current;
    final playing = mine && game.phase == ProphetPhase.playing;
    return OnlineGameFrame(
      setup: setup,
      title: 'Stichprophet',
      actions: [
        IconButton(
          key: const ValueKey('prophetScores'),
          tooltip: 'Punktetabelle',
          onPressed: game.dealt ? _showScores : null,
          icon: const Icon(Icons.table_chart_outlined),
        ),
        if (saveKey != null)
          RestartButton(
            onRestart: () {
              game = ProphetGame(players: players, first: round);
              _deal();
            },
          ),
      ],
      child: Stack(
        children: [
          Column(
            children: [
              TurnBanner(
                text: _status(),
                highlight: mine || game.isOver,
                color: game.trump >= 0
                    ? prophetColors[game.trump].withValues(alpha: 0.35)
                    : null,
              ),
              if (game.dealt) _info(),
              if (game.dealt) _seats(),
              Expanded(child: _table()),
              if (mine && game.phase == ProphetPhase.bidding) _bidButtons(),
              if (mine && game.phase == ProphetPhase.trumpChoice)
                _trumpButtons(),
              if (game.phase == ProphetPhase.roundOver && _canDeal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: FilledButton.icon(
                    key: const ValueKey('prophetNext'),
                    onPressed: () {
                      _nextRound?.cancel();
                      _deal();
                    },
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Nächste Runde'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final c in hand)
                      GestureDetector(
                        key: ValueKey('pc$c'),
                        onTap: playing && game.canPlay(c)
                            ? () => _act(['play', c], game.current)
                            : null,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 150),
                          offset: playing && game.canPlay(c)
                              ? const Offset(0, -0.08)
                              : Offset.zero,
                          child: Opacity(
                            opacity: !playing || game.canPlay(c) ? 1 : 0.45,
                            child: ProphetCardView(
                              card: c,
                              width: hand.length > 12 ? 40 : 48,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (game.isOver)
                GameOverActions(
                  setup: setup,
                  winnerSeats: game.winners(),
                  onRematch: _again,
                ),
            ],
          ),
          if (_stars)
            const Positioned.fill(child: IgnorePointer(child: _Stars())),
          if (_needsHandover)
            Positioned.fill(
              child: PassDeviceCover(
                playerName: _name(game.current),
                onReady: () => setState(() => _viewer = game.current),
              ),
            ),
        ],
      ),
    );
  }

  static int _handOrder(int a, int b) {
    int key(int c) {
      if (PCard.isWizard(c)) return 100;
      if (PCard.isFool(c)) return -1;
      return PCard.color(c) * 20 + PCard.value(c);
    }

    return key(a).compareTo(key(b));
  }

  /// Round and trump.
  Widget _info() {
    final t = game.trumpCard;
    final trumpText = game.trump >= 0
        ? 'Trumpf: ${prophetColorNames[game.trump]}'
        : (game.phase == ProphetPhase.trumpChoice
              ? 'Trumpf wird gewählt'
              : 'Kein Trumpf');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 2,
        children: [
          Text(
            'Runde ${game.cardsThisRound}/${game.rounds}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t != null) ...[
                ProphetCardView(card: t, width: 22),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  trumpText,
                  key: const ValueKey('prophetTrump'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: game.trump >= 0 ? prophetColors[game.trump] : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Every player with prediction, tricks and points.
  Widget _seats() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final finished =
        game.phase == ProphetPhase.roundOver || game.phase == ProphetPhase.over;
    Widget tile(int p) => Container(
      key: ValueKey('prophetSeat$p'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: finished
            ? (game.exact.contains(p)
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.red.withValues(alpha: 0.15))
            : scheme.surfaceContainerHighest,
        border: Border.all(
          color: p == game.toMove ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (p == game.dealer)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(Icons.back_hand_outlined, size: 13),
                ),
              Flexible(
                child: Text(
                  _name(p),
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Stiche ${game.won[p]}/${game.bids[p] ?? '?'}',
            style: text.bodySmall,
          ),
          Text('${game.scores[p]} Pkt.', style: text.bodySmall),
        ],
      ),
    );
    // Up to four players side by side, more in two rows.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: players <= 4
          ? Row(
              children: [
                for (var p = 0; p < players; p++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: tile(p),
                    ),
                  ),
              ],
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (var p = 0; p < players; p++)
                  SizedBox(width: 108, child: tile(p)),
              ],
            ),
    );
  }

  /// The trick on the table, with names.
  Widget _table() {
    if (!game.dealt) return const SizedBox();
    final trick = game.trick;
    final full = trick.length == players;
    final winner = full ? game.lastWinner : null;
    // Shrinks instead of overflowing (small screens, six cards).
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trick.isEmpty && game.phase == ProphetPhase.playing)
                Text(
                  '${_name(game.current)} spielt aus',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              if (trick.isEmpty && game.phase != ProphetPhase.playing)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (game.trumpCard case final t?)
                      ProphetCardView(card: t, width: 70)
                    else
                      const Icon(Icons.block, size: 48),
                    const SizedBox(height: 6),
                    Text(
                      game.trumpCard == null
                          ? 'Letzte Runde: kein Trumpf'
                          : 'Trumpfkarte',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              for (final (seat, card) in trick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: seat == winner ? 1.12 : 1,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: seat == winner
                                  ? Colors.amber
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: ProphetCardView(card: card, width: 58),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 72,
                        child: Text(
                          seat == winner ? '${_name(seat)} ✓' : _name(seat),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: seat == winner
                                    ? FontWeight.bold
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bidButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Text(
            'Ansagen bisher: ${game.bids.whereType<int>().fold(0, (a, b) => a + b)} '
            'von ${game.cardsThisRound} Stichen',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (var n = 0; n <= game.cardsThisRound; n++)
                SizedBox(
                  width: 48,
                  child: FilledButton.tonal(
                    key: ValueKey('bid$n'),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _act(['bid', n], game.current),
                    child: Text('$n'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trumpButtons() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (var c = 0; c < 4; c++)
            FilledButton(
              key: ValueKey('trump$c'),
              style: FilledButton.styleFrom(backgroundColor: prophetColors[c]),
              onPressed: () => _act(['trump', c], game.current),
              child: Text(prophetColorNames[c]),
            ),
        ],
      ),
    );
  }

  void _showScores() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Table(
              key: const ValueKey('prophetScoreTable'),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: Theme.of(context).dividerColor),
              children: [
                TableRow(
                  children: [
                    _cell('Runde', bold: true),
                    for (var p = 0; p < players; p++)
                      _cell(_name(p), bold: true),
                  ],
                ),
                for (var r = 0; r < game.history.length; r++)
                  TableRow(
                    children: [
                      _cell('${r + 1}'),
                      for (final d in game.history[r])
                        _cell(
                          d > 0 ? '+$d' : '$d',
                          color: d > 0 ? Colors.green : Colors.red,
                        ),
                    ],
                  ),
                TableRow(
                  children: [
                    _cell('Gesamt', bold: true),
                    for (final s in game.scores) _cell('$s', bold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _cell(String text, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : null,
            color: color,
          ),
        ),
      );
}

/// A card face.
class ProphetCardView extends StatelessWidget {
  const ProphetCardView({super.key, required this.card, required this.width});
  final int card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    final c = card;
    final wizard = PCard.isWizard(c), fool = PCard.isFool(c);
    final bg = wizard
        ? const Color(0xFF4A148C)
        : fool
        ? const Color(0xFF90A4AE)
        : prophetColors[PCard.color(c)];
    final label = wizard ? 'Z' : (fool ? 'N' : '${PCard.value(c)}');
    final symbol = wizard ? '🧙' : (fool ? '🤡' : null);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: Colors.white, width: max(1.5, width * 0.05)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  shadows: const [Shadow(blurRadius: 3)],
                ),
              ),
              if (symbol != null)
                Text(symbol, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Falling stars for exact predictions (secret "Glaskugel").
class _Stars extends StatefulWidget {
  const _Stars();

  @override
  State<_Stars> createState() => _StarsState();
}

class _StarsState extends State<_Stars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();
  final _seeds = List.generate(24, (i) => Random(i * 31 + 7).nextDouble());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          for (var i = 0; i < _seeds.length; i++)
            Positioned(
              left: _seeds[i] * box.maxWidth,
              top:
                  (_c.value * 1.3 - _seeds[(i + 5) % _seeds.length] * 0.4) *
                  box.maxHeight,
              child: Opacity(
                opacity: (1 - _c.value).clamp(0.0, 1.0),
                child: Text(
                  i.isEven ? '✨' : '⭐',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
