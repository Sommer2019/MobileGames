import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/play_setup.dart';
import 'stapelfix_logic.dart';

class StapelfixScreen extends StatefulWidget {
  const StapelfixScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<StapelfixScreen> createState() => _StapelfixScreenState();
}

class _StapelfixScreenState extends State<StapelfixScreen>
    with SavedGameState, BotTurns {
  late int round = widget.setup.firstRound;
  late StapelfixGame game = StapelfixGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();
  final StapelfixAi _ai = StapelfixAi();

  /// Picked source: a hand card id, −1 stock, −2 … −5 discard pile.
  int? _selected;
  int? _viewer;

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  bool get _canDeal => !setup.online || setup.isHost;

  @override
  Duration get botDelay => const Duration(milliseconds: 550);

  @override
  String? get saveKey => setup.saveKey('stapelfix');

  @override
  Map<String, dynamic>? saveGame() {
    if (game.isOver || !game.dealt) return null;
    return {'round': round, 'events': game.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = StapelfixGame.replay(players, data['events'] as List, first: round);
  }

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    if (!restoredGame && _canDeal) _deal();
    _viewer = _defaultViewer();
    scheduleBot();
  }

  @override
  void dispose() {
    _sub?.cancel();
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
    if (setup.online) return false;
    final c = game.toMove;
    return c != null && !setup.isBot(c) && c != _viewer;
  }

  @override
  int? get seatToMove => game.toMove;

  @override
  void botAct(int seat) => _act(_ai.choose(game), seat);

  void _deal() => _act([
    'deal',
    _random.nextInt(1 << 30),
    Secrets.on(Secret.jokerRain) ? 36 : 18,
  ], 0);

  void _act(List event, int seat) {
    if (!game.apply(event)) return;
    setup.sendAs(seat, {'t': 'e', 'e': event});
    _after(event);
  }

  void _after(List event) {
    setState(() => _selected = null);
    switch (event.first) {
      case 'deal':
        if (!setup.online) _viewer = _defaultViewer();
        Sound.play(Sfx.card);
      case 'b':
        Sound.play(game.isOver ? Sfx.thud : Sfx.card);
      case 'x':
        Sound.play(Sfx.place);
    }
    persistGame();
    scheduleBot();
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
        if (_canDeal && (!game.dealt || game.isOver)) _deal();
    }
  }

  void _again() {
    if (_canDeal) {
      if (!setup.online) {
        round++;
        game = StapelfixGame(players: players, first: round);
      }
      _deal();
    } else {
      setup.send({'t': 'again'});
    }
  }

  bool get _myTurn {
    final c = game.toMove;
    return c != null &&
        setup.humanControls(c) &&
        !_needsHandover &&
        _viewer == c;
  }

  void _select(int source) {
    if (!_myTurn || game.cardOf(source) == null) return;
    setState(() => _selected = _selected == source ? null : source);
  }

  void _tapBuild(int i) {
    final s = _selected;
    if (!_myTurn || s == null) return;
    if (game.canBuild(s, i)) _act(['b', s, i], game.current);
  }

  void _tapDiscard(int i) {
    if (!_myTurn) return;
    final s = _selected;
    if (s != null && s >= 0) {
      _act(['x', s, i], game.current);
    } else {
      _select(-2 - i);
    }
  }

  String _status() {
    if (!game.dealt) return 'Warte auf das Austeilen …';
    if (game.isOver) {
      final n = setup.seatName(game.winner!);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final c = game.current;
    final n = setup.seatName(c);
    if (setup.isBot(c)) return '$n ist dran …';
    if (!setup.humanControls(c)) return '$n ist dran';
    final who = n == 'Du' ? 'Du bist dran' : '$n ist dran';
    final s = _selected;
    if (s == null) return '$who – Karte wählen';
    if (s >= 0) return 'Auf einen Stapel legen oder ablegen (Zugende)';
    return 'Auf einen Stapel in der Mitte legen';
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    return OnlineGameFrame(
      setup: setup,
      title: 'Stapelfix',
      actions: [
        if (saveKey != null)
          RestartButton(
            onRestart: () {
              game = StapelfixGame(players: players, first: round);
              _deal();
            },
          ),
      ],
      child: Stack(
        children: [
          if (game.dealt)
            Column(
              children: [
                TurnBanner(text: _status(), highlight: _myTurn || game.isOver),
                _opponents(viewer),
                const SizedBox(height: 8),
                Text(
                  'Ziehstapel: ${game.pile.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // Build piles.
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            key: ValueKey('sfBuild$i'),
                            onTap: () => _tapBuild(i),
                            child: _buildPile(i),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                if (viewer != null) _ownArea(viewer),
                if (game.isOver)
                  GameOverActions(
                    setup: setup,
                    winnerSeats: [game.winner!],
                    onRematch: _again,
                  ),
              ],
            )
          else
            const Center(child: Text('Warte auf das Austeilen …')),
          if (_needsHandover)
            Positioned.fill(
              child: PassDeviceCover(
                playerName: setup.seatName(game.current),
                onReady: () => setState(() => _viewer = game.current),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPile(int i) {
    final pile = game.build[i];
    final fits = _selected != null && game.canBuild(_selected!, i);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fits ? Colors.amber : Colors.transparent,
          width: 3,
        ),
      ),
      child: pile.isEmpty
          ? SfCardView.empty(width: 72, label: '1')
          : SfCardView(card: pile.last, width: 72, shownValue: pile.length),
    );
  }

  Widget _opponents(int? viewer) {
    final others = [
      for (var p = 0; p < players; p++)
        if (p != viewer) p,
    ];
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final p in others)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: p == game.toMove ? Colors.amber : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${setup.seatName(p)} · Stapel ${game.stock[p].length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SfCardView(card: game.stockTop(p), width: 32),
                      const SizedBox(width: 8),
                      for (var d = 0; d < 4; d++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: game.discardTop(p, d) == null
                              ? SfCardView.empty(width: 26)
                              : SfCardView(
                                  card: game.discardTop(p, d),
                                  width: 26,
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _ownArea(int me) {
    final hand = game.hands[me];
    Widget pick(int source, Widget child) => AnimatedSlide(
      duration: const Duration(milliseconds: 120),
      offset: _selected == source ? const Offset(0, -0.12) : Offset.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: _selected == source
              ? const [BoxShadow(color: Colors.amber, blurRadius: 10)]
              : null,
        ),
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        children: [
          // Scales down on narrow screens.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  children: [
                    Text('Stapel: ${game.stock[me].length}'),
                    const SizedBox(height: 4),
                    GestureDetector(
                      key: const ValueKey('sfStock'),
                      onTap: () => _select(-1),
                      child: pick(
                        -1,
                        SfCardView(card: game.stockTop(me), width: 76),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                for (var d = 0; d < 4; d++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      key: ValueKey('sfDiscard$d'),
                      onTap: () => _tapDiscard(d),
                      child: Column(
                        children: [
                          Text(
                            '${game.discards[me][d].length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          pick(
                            -2 - d,
                            game.discardTop(me, d) == null
                                ? SfCardView.empty(width: 56, label: '')
                                : SfCardView(
                                    card: game.discardTop(me, d),
                                    width: 56,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      key: ValueKey('sfHand$c'),
                      onTap: () => _select(c),
                      child: pick(c, SfCardView(card: c, width: 64)),
                    ),
                  ),
                if (hand.isEmpty && _myTurn)
                  FilledButton(
                    key: const ValueKey('sfEnd'),
                    onPressed: () => _act(['x', -1, -1], game.current),
                    child: const Text('Zug beenden'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A Stapelfix card: 1–4 blue, 5–8 green, 9–12 red, jokers orange.
class SfCardView extends StatelessWidget {
  const SfCardView({
    super.key,
    required this.card,
    required this.width,
    this.shownValue,
  }) : label = null;

  const SfCardView.empty({super.key, required this.width, this.label = ''})
    : card = null,
      shownValue = null;

  final int? card;
  final double width;

  /// Value a joker stands for on a build pile.
  final int? shownValue;
  final String? label;

  static Color colorOf(int value) => value == 0
      ? const Color(0xFFFB8C00)
      : value <= 4
      ? const Color(0xFF1E88E5)
      : value <= 8
      ? const Color(0xFF43A047)
      : const Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final c = card;
    if (c == null) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label ?? '',
          style: TextStyle(
            fontSize: width * 0.4,
            color: Theme.of(context).colorScheme.outline,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    final v = StapelfixGame.value(c);
    final joker = StapelfixGame.isJoker(c);
    final color = colorOf(v);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: color, width: max(2, width * 0.06)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                joker ? (shownValue != null ? '$shownValue' : '★') : '$v',
                style: TextStyle(
                  color: color,
                  fontSize: width * 0.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (joker && shownValue != null)
                Text(
                  '★',
                  style: TextStyle(color: color, fontSize: width * 0.2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
