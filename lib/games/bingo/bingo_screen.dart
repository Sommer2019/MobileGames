import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'bingo_logic.dart';

const bingoColors = [
  Color(0xFF1E88E5), // B
  Color(0xFFE53935), // I
  Color(0xFF8E24AA), // N
  Color(0xFF43A047), // G
  Color(0xFFFB8C00), // O
];

Color bingoColor(int ball) => bingoColors[(ball - 1) ~/ 15];

class BingoScreen extends StatefulWidget {
  const BingoScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<BingoScreen> createState() => _BingoScreenState();
}

class _BingoScreenState extends State<BingoScreen> {
  BingoGame? game;
  StreamSubscription<RoomMessage>? _sub;
  final Random _random = Random();
  Timer? _drawTimer;
  final Map<int, Timer> _botClaims = {};

  /// Numbers marked on the own card.
  final Set<int> _marked = {};

  /// Own claim sent, waiting for the host.
  bool _claimed = false;

  PlaySetup get setup => widget.setup;
  int get players => setup.players;

  /// The host calls the numbers (offline: this device).
  bool get _caller => !setup.online || setup.isHost;

  int? get _me =>
      setup.spectator || setup.isBot(setup.mySeat) ? null : setup.mySeat;

  /// Card shown although it is not ours: the friend's card for
  /// spectators, the first computer's in the Bot-Arena.
  int? get _shown =>
      _me ?? (setup.spectator ? setup.mySeat : (setup.online ? null : 0));

  bool get _watching => _me == null && _shown != null;

  /// Bingo turbo (secret): balls come twice as fast.
  bool get _turbo => Secrets.on(Secret.bingoTurbo);
  Duration get _interval => Duration(milliseconds: _turbo ? 1800 : 3600);

  @override
  void initState() {
    super.initState();
    _sub = setup.listen(_onMessage);
    if (_caller) _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _drawTimer?.cancel();
    for (final t in _botClaims.values) {
      t.cancel();
    }
    _botClaims.clear();
  }

  void _start() {
    final seed = _random.nextInt(1 << 30);
    setup.send({'t': 'start', 'seed': seed});
    _newGame(seed);
    _drawTimer = Timer.periodic(_interval, (_) => _draw());
  }

  void _newGame(int seed) {
    _stopTimers();
    setState(() {
      game = BingoGame(players: players, seed: seed);
      _marked.clear();
      _claimed = false;
    });
  }

  void _draw() {
    final g = game;
    if (g == null || !g.draw()) {
      _drawTimer?.cancel();
      return;
    }
    setup.send({'t': 'draw', 'n': g.drawn});
    _afterDraw();
  }

  void _afterDraw() {
    setState(() {});
    Sound.play(Sfx.click);
    if (!_caller) return;
    // Computer players notice their bingo after a moment.
    final g = game!;
    for (final b in setup.botSeats) {
      if (_botClaims.containsKey(b) || !g.hasBingo(b)) continue;
      _botClaims[b] = Timer(
        Duration(milliseconds: 1200 + _random.nextInt(2500)),
        () => _judge(b),
      );
    }
  }

  /// The caller decides on a claim.
  void _judge(int seat) {
    final g = game;
    if (g == null || !g.claim(seat)) return;
    _stopTimers();
    setup.send({'t': 'win', 's': seat});
    _won();
  }

  void _won() {
    setState(() {});
    Sound.play(game!.winner == _me ? Sfx.win : Sfx.lose);
  }

  void _onMessage(RoomMessage m) {
    final d = m.data;
    final g = game;
    switch (d['t']) {
      case 'start':
        final s = d['seed'];
        if (m.seat == 0 && s is int) _newGame(s);
      case 'draw':
        final n = d['n'];
        if (m.seat != 0 || g == null || n is! int) return;
        if (n > g.drawn && n <= g.order.length && !g.isOver) {
          g.drawn = n;
          _afterDraw();
        }
      case 'win':
        final s = d['s'];
        if (m.seat != 0 || g == null || s is! int || g.isOver) return;
        if (g.claim(s)) {
          _won();
        } else if (s >= 0 && s < players) {
          // Trust the host even if a ball got lost on the way.
          g.winner = s;
          _won();
        }
      case 'bingo':
        if (_caller) _judge(m.seat);
      case 'again':
        if (_caller && (g == null || g.isOver)) _start();
    }
  }

  void _tapCell(int number) {
    final g = game;
    if (g == null || g.isOver || number == 0 || _me == null) return;
    if (!g.drawnSet.contains(number)) return;
    setState(() {
      if (!_marked.remove(number)) _marked.add(number);
    });
    Sound.play(Sfx.place);
  }

  void _callBingo() {
    final g = game, me = _me;
    if (g == null || me == null || g.isOver || _claimed) return;
    if (!g.markedBingo(me, _marked)) return;
    if (_caller) {
      _judge(me);
    } else {
      setState(() => _claimed = true);
      setup.send({'t': 'bingo'});
    }
  }

  void _again() {
    if (_caller) {
      _start();
    } else {
      setup.send({'t': 'again'});
    }
  }

  String _status(BingoGame g) {
    if (g.isOver) {
      final n = setup.seatName(g.winner!);
      return n == 'Du' ? 'BINGO! Du hast gewonnen! 🎉' : '$n hat Bingo!';
    }
    if (_claimed) return 'Bingo gerufen – wird geprüft …';
    if (g.drawn == 0) return 'Gleich geht’s los …';
    return 'Kugel ${g.drawn} von 75${_turbo ? ' · Turbo' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    return OnlineGameFrame(
      setup: setup,
      title: 'Bingo',
      child: g == null
          ? const Center(child: Text('Warte auf den Spielleiter …'))
          : _body(context, g),
    );
  }

  Widget _body(BuildContext context, BingoGame g) {
    final me = _me;
    final canCall = me != null && !g.isOver && g.markedBingo(me, _marked);
    final recent = [
      for (var i = g.drawn - 2; i >= max(0, g.drawn - 6); i--) g.order[i],
    ];
    return Column(
      children: [
        TurnBanner(
          text: _status(g),
          highlight: g.isOver || canCall,
          color: g.isOver && g.winner == me
              ? Colors.amber.withValues(alpha: 0.5)
              : null,
        ),
        // The ball just drawn and the ones before.
        SizedBox(
          height: 84,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: g.lastBall == null
                    ? const SizedBox(width: 76)
                    : _Ball(
                        key: ValueKey(g.lastBall),
                        number: g.lastBall!,
                        size: 76,
                      ),
              ),
              const SizedBox(width: 12),
              for (final b in recent)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: _Ball(number: b, size: 38),
                ),
            ],
          ),
        ),
        if (players > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (var p = 0; p < players; p++)
                  if (p != _shown)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${setup.seatName(p)}: '
                        '${g.missing(p) == 0 ? 'BINGO?' : '${g.missing(p)} fehlen'}',
                      ),
                    ),
              ],
            ),
          ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 5 / 6,
                child: me != null
                    ? _card(context, g, me)
                    : _watching
                    ? _card(context, g, _shown!)
                    : const SizedBox(),
              ),
            ),
          ),
        ),
        if (g.isOver)
          GameOverActions(
            setup: setup,
            winnerSeats: [g.winner!],
            onRematch: _again,
          )
        else if (me != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                key: const ValueKey('bingoCall'),
                onPressed: canCall && !_claimed ? _callBingo : null,
                child: const Text(
                  'BINGO!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, BingoGame g, int me) {
    final card = g.cards[me];
    final drawn = g.drawnSet;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var c = 0; c < 5; c++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: bingoColors[c],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      BingoGame.letters[c],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var r = 0; r < 5; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < 5; c++)
                  Expanded(child: _cell(card[r * 5 + c], drawn, scheme)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int n, Set<int> drawn, ColorScheme scheme) {
    final free = n == 0;
    // Watching the computers: their card marks itself.
    final marked =
        free || _marked.contains(n) || (_watching && drawn.contains(n));
    return GestureDetector(
      key: ValueKey('bingoCell$n'),
      onTap: () => _tapCell(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: !marked && drawn.contains(n)
                ? Colors.amber
                : scheme.outlineVariant,
            width: !marked && drawn.contains(n) ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              free ? '★' : '$n',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            AnimatedScale(
              scale: marked ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: FractionallySizedBox(
                widthFactor: 0.8,
                heightFactor: 0.8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (free ? Colors.amber : Colors.red).withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ball extends StatelessWidget {
  const _Ball({super.key, required this.number, required this.size});
  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = bingoColor(number);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.35),
          colors: [Color.lerp(color, Colors.white, 0.5)!, color],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.62,
        height: size * 0.62,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text(
              '${BingoGame.letterOf(number)}\n$number',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                height: 1,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
