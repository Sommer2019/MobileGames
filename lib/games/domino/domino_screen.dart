import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/bot_turns.dart';
import '../../ui/play_setup.dart';
import 'domino_logic.dart';

const dominoColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
];

class DominoScreen extends StatefulWidget {
  const DominoScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<DominoScreen> createState() => _DominoScreenState();
}

class _DominoScreenState extends State<DominoScreen>
    with SavedGameState, BotTurns, SingleTickerProviderStateMixin {
  late int round = widget.setup.firstRound;
  late DominoMatch match = DominoMatch(players: players, first: round);
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();

  /// Tile picked in the hand that fits on both ends.
  int? _selected;

  /// Local seat whose hand is shown (pass and play with several humans).
  int? _viewer;

  /// Domino effect (secret): the line topples at the end of a round.
  late final AnimationController _topple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  /// Only the host (or the device offline) deals, so all hands match.
  bool get _canDeal => !setup.online || setup.isHost;

  @override
  String? get saveKey => setup.saveKey('domino');

  @override
  Map<String, dynamic>? saveGame() {
    if (match.isOver || !match.dealt) return null;
    return {'round': round, 'events': match.events};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    match = DominoMatch.replay(players, data['events'] as List, first: round);
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
    _topple.dispose();
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
    final c = match.toMove;
    return c != null && !setup.isBot(c) ? c : humans.first;
  }

  /// Several people share the device and someone else is up now.
  bool get _needsHandover {
    if (setup.online) return false;
    final c = match.toMove;
    return c != null && !setup.isBot(c) && c != _viewer;
  }

  @override
  int? get seatToMove => match.toMove;

  @override
  void botAct(int seat) => _act(DominoAi.choose(match), seat);

  void _deal() {
    _act(['deal', _random.nextInt(1 << 30)], 0);
  }

  void _act(List event, int seat) {
    final wasOver = match.roundOver;
    if (!match.apply(event)) return;
    setup.sendAs(seat, {'t': 'e', 'e': event});
    _after(event, wasOver);
  }

  void _after(List event, bool wasOver) {
    setState(() => _selected = null);
    switch (event.first) {
      case 'deal':
        _topple.reset();
        if (!setup.online && !_needsHandover) _viewer = _defaultViewer();
      case 'play':
        Sound.play(Sfx.place);
      case 'draw':
        Sound.play(Sfx.card);
      case 'pass':
        Sound.play(Sfx.click);
    }
    if (!wasOver && match.roundOver) {
      if (!match.isOver) Sound.play(Sfx.thud);
      if (Secrets.on(Secret.dominoEffect)) _topple.forward(from: 0);
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
        // Deals only come from the host, moves from the player to move.
        if (e.first == 'deal' ? m.seat != 0 : m.seat != match.current) return;
        final wasOver = match.roundOver;
        if (match.apply(List.from(e))) _after(e, wasOver);
      case 'again':
        if (_canDeal && match.roundOver) _deal();
    }
  }

  void _next() {
    if (_canDeal) {
      _deal();
    } else {
      setup.send({'t': 'again'});
    }
  }

  void _restart() {
    setState(() {
      round++;
      match = DominoMatch(players: players, first: round);
    });
    _deal();
  }

  bool get _myTurn {
    final c = match.toMove;
    return c != null && setup.humanControls(c) && !_needsHandover;
  }

  void _tapTile(int tile) {
    if (!_myTurn) return;
    final sides = match.sidesFor(tile);
    if (sides.isEmpty) return;
    if (sides.length == 1 || match.left == match.right) {
      _act(['play', tile, sides.last], match.current);
    } else {
      setState(() => _selected = _selected == tile ? null : tile);
    }
  }

  void _tapEnd(int side) {
    final t = _selected;
    if (t == null || !_myTurn) return;
    _act(['play', t, side], match.current);
  }

  String _status() {
    if (!match.dealt) return 'Warte auf das Austeilen …';
    if (match.isOver) {
      final n = setup.seatName(match.winner!);
      return n == 'Du' ? 'Du gewinnst das Match! 🎉' : '$n gewinnt das Match!';
    }
    if (match.roundOver) {
      final w = match.roundWinner;
      final how = match.blocked ? 'Blockiert – ' : '';
      if (w == null) return '${how}Unentschieden, keine Punkte';
      final n = setup.seatName(w);
      return '$how${n == 'Du' ? 'Du bekommst' : '$n bekommt'} '
          '${match.roundPoints} Punkte';
    }
    final c = match.current;
    final n = setup.seatName(c);
    if (setup.isBot(c)) return '$n überlegt …';
    if (!setup.humanControls(c)) return '$n ist dran';
    final who = n == 'Du' ? 'Du bist dran' : '$n ist dran';
    if (match.canDraw) return '$who – kein passender Stein, ziehen';
    if (match.mustPass) return '$who – nichts passt, passen';
    if (_selected != null) return 'Links oder rechts anlegen?';
    return who;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewer = _viewer;
    final hand = viewer == null || !match.dealt ? <int>[] : match.hands[viewer];
    final playable = _myTurn && viewer == match.current
        ? match.playable().toSet()
        : <int>{};
    return OnlineGameFrame(
      setup: setup,
      title: 'Domino',
      actions: [if (saveKey != null) RestartButton(onRestart: _restart)],
      child: Stack(
        children: [
          Column(
            children: [
              TurnBanner(
                text: _status(),
                highlight: _myTurn || match.roundOver,
                color:
                    dominoColors[(match.isOver
                                ? match.winner!
                                : match.current) %
                            4]
                        .withValues(alpha: 0.3),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    for (var p = 0; p < players; p++)
                      Chip(
                        avatar: CircleAvatar(
                          backgroundColor: dominoColors[p],
                          child: Text(
                            match.dealt ? '${match.hands[p].length}' : '',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        label: Text('${setup.seatName(p)}: ${match.scores[p]}'),
                        side: p == match.toMove
                            ? BorderSide(color: dominoColors[p], width: 2)
                            : null,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: AnimatedBuilder(
                      animation: _topple,
                      builder: (context, _) => Wrap(
                        spacing: 3,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_selected != null) _endTarget(0),
                          for (var i = 0; i < match.line.length; i++)
                            _toppling(i, match.line[i]),
                          if (_selected != null) _endTarget(1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (match.dealt && !match.roundOver)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text('Talon: ${match.boneyard.length}'),
                      const Spacer(),
                      if (_myTurn && match.canDraw)
                        FilledButton.tonalIcon(
                          key: const ValueKey('dominoDraw'),
                          onPressed: () => _act(['draw'], match.current),
                          icon: const Icon(Icons.add),
                          label: const Text('Ziehen'),
                        ),
                      if (_myTurn && match.mustPass)
                        FilledButton.tonalIcon(
                          key: const ValueKey('dominoPass'),
                          onPressed: () => _act(['pass'], match.current),
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Passen'),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final t in hand)
                      GestureDetector(
                        key: ValueKey('domino$t'),
                        onTap: () => _tapTile(t),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: playable.isEmpty || playable.contains(t)
                              ? 1
                              : 0.45,
                          child: DominoTile(
                            a: Domino.tiles[t].$1,
                            b: Domino.tiles[t].$2,
                            vertical: true,
                            size: 26,
                            highlight: t == _selected
                                ? scheme.primary
                                : playable.contains(t)
                                ? Colors.amber
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (match.isOver)
                GameOverActions(
                  setup: setup,
                  winnerSeats: [match.winner!],
                  onRematch: _next,
                  rematchLabel: setup.online ? 'Revanche' : 'Neues Match',
                )
              else if (match.roundOver && match.dealt)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    key: const ValueKey('dominoNext'),
                    onPressed: _next,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Nächste Runde'),
                  ),
                ),
            ],
          ),
          if (_needsHandover)
            Positioned.fill(
              child: PassDeviceCover(
                playerName: setup.seatName(match.current),
                onReady: () => setState(() => _viewer = match.current),
              ),
            ),
        ],
      ),
    );
  }

  Widget _endTarget(int side) => GestureDetector(
    key: ValueKey('dominoEnd$side'),
    onTap: () => _tapEnd(side),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.35),
        border: Border.all(color: Colors.amber, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        side == 0 ? Icons.arrow_back : Icons.arrow_forward,
        color: Colors.white,
      ),
    ),
  );

  /// A tile of the line; falls over like a domino with the secret on.
  Widget _toppling(int i, PlacedTile p) {
    final n = match.line.length;
    final t = _topple.value * (n + 6) - i;
    final fall = (t / 6).clamp(0.0, 1.0);
    final tile = DominoTile(a: p.a, b: p.b, vertical: p.a == p.b, size: 20);
    if (fall == 0) return tile;
    return Transform.rotate(
      angle: Curves.easeIn.transform(fall) * pi / 2.4,
      alignment: Alignment.bottomRight,
      child: tile,
    );
  }
}

/// A domino tile with pips; [size] is the edge of one half.
class DominoTile extends StatelessWidget {
  const DominoTile({
    super.key,
    required this.a,
    required this.b,
    this.vertical = false,
    this.size = 24,
    this.highlight,
  });
  final int a;
  final int b;
  final bool vertical;
  final double size;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final w = vertical ? size : size * 2, h = vertical ? size * 2 : size;
    return Container(
      width: w + 2,
      height: h + 2,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(
          color: highlight ?? Colors.black54,
          width: highlight != null ? 3 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
      child: CustomPaint(painter: _TilePainter(a, b, vertical)),
    );
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.a, this.b, this.vertical);
  final int a;
  final int b;
  final bool vertical;

  static const _pips = {
    0: <(double, double)>[],
    1: [(0.5, 0.5)],
    2: [(0.25, 0.25), (0.75, 0.75)],
    3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
    6: [
      (0.25, 0.22),
      (0.75, 0.22),
      (0.25, 0.5),
      (0.75, 0.5),
      (0.25, 0.78),
      (0.75, 0.78),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final half = vertical
        ? Size(size.width, size.height / 2)
        : Size(size.width / 2, size.height);
    final second = vertical ? Offset(0, half.height) : Offset(half.width, 0);
    final line = Paint()
      ..color = Colors.black45
      ..strokeWidth = 1.2;
    if (vertical) {
      canvas.drawLine(
        Offset(half.width * 0.15, half.height),
        Offset(half.width * 0.85, half.height),
        line,
      );
    } else {
      canvas.drawLine(
        Offset(half.width, half.height * 0.15),
        Offset(half.width, half.height * 0.85),
        line,
      );
    }
    final pip = Paint()..color = const Color(0xFF212121);
    final r = half.shortestSide * 0.09;
    for (final (n, o) in [(a, Offset.zero), (b, second)]) {
      for (final (x, y) in _pips[n]!) {
        canvas.drawCircle(o + Offset(x * half.width, y * half.height), r, pip);
      }
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.a != a || old.b != b || old.vertical != vertical;
}
