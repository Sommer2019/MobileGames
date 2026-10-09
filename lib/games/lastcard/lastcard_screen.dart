import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/play_setup.dart';
import 'lastcard_logic.dart';

const lcColors = [
  Color(0xFFE53935), // Rot
  Color(0xFFFDD835), // Gelb
  Color(0xFF43A047), // Grün
  Color(0xFF1E88E5), // Blau
];
const lcColorNames = ['Rot', 'Gelb', 'Grün', 'Blau'];

class LastCardScreen extends StatefulWidget {
  const LastCardScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<LastCardScreen> createState() => _LastCardScreenState();
}

class _LastCardScreenState extends State<LastCardScreen>
    with SavedGameState, GameMirror, SavedGameMirror, BotTurns {
  @override
  String? get mirrorGame => setup.online ? null : 'lastcard';

  @override
  Map<String, dynamic> get mirrorSetup => setup.mirrorInfo;

  late int round = widget.setup.firstRound;
  late LastCardGame game = LastCardGame(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();

  /// Local seat whose hand is shown (pass and play with several humans).
  int? _viewer;

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  bool get _canDeal => setup.runsGame;

  @override
  String? get saveKey => setup.saveKey('lastcard');

  @override
  Map<String, dynamic>? saveGame() {
    if (!savingForMirror && (game.isOver || !game.dealt)) return null;
    return {'round': round, 'events': game.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    game = LastCardGame.replay(players, data['events'] as List, first: round);
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
    if (setup.online || setup.spectator) return false;
    final c = game.toMove;
    return c != null && !setup.isBot(c) && c != _viewer;
  }

  @override
  int? get seatToMove => game.toMove;

  @override
  void botAct(int seat) => _act(LastCardAi(_random).choose(game), seat);

  void _deal() => _act([
    'deal',
    _random.nextInt(1 << 30),
    Secrets.on(Secret.lastCardStack),
  ], 0);

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
        Sound.play(Sfx.card);
      case 'play':
        Sound.play(game.isOver ? Sfx.thud : Sfx.card);
      case 'draw':
        Sound.play(Sfx.card);
      case 'last':
        Sound.play(Sfx.click);
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
      if (!setup.online) round++;
      game = LastCardGame(players: players, first: round);
      _deal();
    } else {
      setup.send({'t': 'again'});
    }
  }

  bool get _myTurn {
    final c = game.toMove;
    return c != null && setup.humanControls(c) && !_needsHandover;
  }

  Future<void> _tapCard(int card) async {
    if (!_myTurn || !game.canPlay(card)) return;
    var color = -1;
    if (LcCard.isWild(card)) {
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Welche Farbe?'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (var c = 0; c < 4; c++)
                    InkWell(
                      key: ValueKey('lcColor$c'),
                      onTap: () => Navigator.pop(context, c),
                      borderRadius: BorderRadius.circular(32),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: lcColors[c],
                        child: Text(
                          lcColorNames[c],
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      color = picked;
    }
    _act(['play', card, color], game.current);
  }

  String _status() {
    if (!game.dealt) return 'Warte auf das Austeilen …';
    if (game.isOver) {
      final n = setup.seatName(game.winner!);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final pen = game.penalized;
    final penText = pen == null
        ? ''
        : '${setup.seatName(pen)} hat „Letzte Karte“ vergessen: +2! ';
    final c = game.current;
    final n = setup.seatName(c);
    if (setup.isBot(c)) return '$penText$n ist dran …';
    if (!setup.humanControls(c)) return '$penText$n ist dran';
    final who = n == 'Du' ? 'Du bist dran' : '$n ist dran';
    if (game.pendingDraw > 0) {
      return '$penText$who – +${game.pendingDraw}: drauflegen oder ziehen';
    }
    if (game.drawn != null) return '$who – gezogene Karte spielen?';
    return '$penText$who';
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    final hand = viewer == null || !game.dealt
        ? <int>[]
        : (List.of(game.hands[viewer])..sort(_handOrder));
    final mine = _myTurn && viewer == game.current;
    return OnlineGameFrame(
      setup: setup,
      title: 'Letzte Karte',
      actions: [
        if (saveKey != null)
          RestartButton(
            onRestart: () {
              game = LastCardGame(players: players, first: round);
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
                color: game.dealt
                    ? lcColors[game.color].withValues(alpha: 0.4)
                    : null,
              ),
              _opponents(viewer),
              Expanded(child: _table(mine)),
              if (game.dealt && !game.isOver)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('lcCall'),
                        onPressed: mine && game.canCall
                            ? () => _act(['last'], game.current)
                            : null,
                        icon: const Icon(Icons.campaign),
                        label: Text(
                          game.called && mine ? 'Gerufen!' : 'Letzte Karte!',
                        ),
                      ),
                      if (mine && game.drawn != null)
                        OutlinedButton(
                          key: const ValueKey('lcKeep'),
                          onPressed: () => _act(['keep'], game.current),
                          child: const Text('Behalten'),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final c in hand)
                      GestureDetector(
                        key: ValueKey('lc$c'),
                        onTap: () => _tapCard(c),
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 150),
                          offset: mine && game.canPlay(c)
                              ? const Offset(0, -0.08)
                              : Offset.zero,
                          child: Opacity(
                            opacity: !mine || game.canPlay(c) ? 1 : 0.5,
                            child: LcCardView(card: c, width: 52),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (game.isOver)
                GameOverActions(
                  setup: setup,
                  winnerSeats: [game.winner!],
                  onRematch: _again,
                ),
            ],
          ),
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

  static int _handOrder(int a, int b) {
    int key(int c) =>
        (LcCard.isWild(c) ? 4 : LcCard.color(c)) * 20 + LcCard.kind(c);
    return key(a).compareTo(key(b));
  }

  Widget _opponents(int? viewer) {
    if (!game.dealt) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            game.direction > 0 ? Icons.rotate_right : Icons.rotate_left,
            size: 20,
          ),
          for (var p = 0; p < players; p++)
            if (p != viewer)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.style, size: 18),
                label: Text(
                  '${setup.seatName(p)}: ${game.hands[p].length}'
                  '${game.hands[p].length == 1 ? ' ‼' : ''}',
                ),
                side: p == game.toMove
                    ? BorderSide(color: lcColors[game.color], width: 2)
                    : null,
              ),
        ],
      ),
    );
  }

  Widget _table(bool mine) {
    if (!game.dealt) return const SizedBox();
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            key: const ValueKey('lcPile'),
            onTap: mine && game.drawn == null
                ? () => _act(['draw'], game.current)
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const LcCardView(card: null, width: 84),
                if (game.pendingDraw > 0)
                  Positioned(
                    right: -10,
                    top: -10,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.black,
                      child: Text(
                        '+${game.pendingDraw}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: Tween(begin: 1.3, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Container(
              key: ValueKey(game.discard.length),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: lcColors[game.color], width: 5),
              ),
              child: LcCardView(card: game.top, width: 96),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card face (or its back when [card] is null).
class LcCardView extends StatelessWidget {
  const LcCardView({super.key, required this.card, required this.width});
  final int? card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.5;
    final c = card;
    final bg = c == null
        ? const Color(0xFF212121)
        : LcCard.isWild(c)
        ? const Color(0xFF212121)
        : lcColors[LcCard.color(c)];
    final label = c == null ? '' : _label(c);
    final fg = c != null && LcCard.color(c) == 1 ? Colors.black87 : bg;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: Colors.white, width: width * 0.05),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2)),
        ],
      ),
      child: Center(
        child: Transform.rotate(
          angle: -0.5,
          child: Container(
            width: width * 0.78,
            height: h * 0.62,
            decoration: BoxDecoration(
              color: c == null ? const Color(0xFFE53935) : Colors.white,
              borderRadius: BorderRadius.all(
                Radius.elliptical(width * 0.39, h * 0.31),
              ),
              gradient: c != null && LcCard.isWild(c)
                  ? const SweepGradient(
                      colors: [...lcColors, Color(0xFFE53935)],
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: 0.5,
              child: c == null
                  ? Text(
                      'LK',
                      style: TextStyle(
                        color: const Color(0xFFFDD835),
                        fontWeight: FontWeight.w900,
                        fontSize: width * 0.32,
                      ),
                    )
                  : FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: LcCard.isWild(c) ? Colors.white : fg,
                            fontWeight: FontWeight.w900,
                            fontSize: width * 0.42,
                            shadows: LcCard.isWild(c)
                                ? const [Shadow(blurRadius: 3)]
                                : null,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(int c) => switch (LcCard.kind(c)) {
    kSkip => '⊘',
    kReverse => '⇄',
    kDraw2 => '+2',
    kWild => '★',
    kWild4 => '+4',
    final n => '$n',
  };
}
