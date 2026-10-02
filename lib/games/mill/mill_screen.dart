import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net/room.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'mill_logic.dart';

/// Board coordinates (0..6 grid) of the 24 points.
const List<(int, int)> _corners = [
  (0, 0),
  (1, 0),
  (2, 0),
  (2, 1),
  (2, 2),
  (1, 2),
  (0, 2),
  (0, 1),
];

Offset pointPosition(int i) {
  final ring = i ~/ 8;
  final (x, y) = _corners[i % 8];
  final size = 6 - ring * 2; // 6, 4, 2
  return Offset(ring + x * size / 2, ring + y * size / 2);
}

class MillScreen extends StatefulWidget {
  const MillScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<MillScreen> createState() => _MillScreenState();
}

class _MillScreenState extends State<MillScreen> {
  MillGame game = MillGame();
  late int round = widget.setup.firstRound;
  int? selected;
  StreamSubscription<RoomMessage>? _sub;
  bool _aiThinking = false;

  /// Player number (1 = white) of this device; swaps every round.
  int get me => (widget.setup.isHost == round.isEven) ? 1 : 2;

  @override
  void initState() {
    super.initState();
    _sub = widget.setup.listen((m) => _onMessage(m.data));
    _maybeAi();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> m) {
    if (m['t'] == 'rematch') {
      _reset(send: false);
      return;
    }
    if (game.turn == me) return;
    Sound.play(Sfx.place);
    setState(() {
      switch (m['t']) {
        case 'place':
          game.place(m['p'] as int);
        case 'move':
          game.move(m['from'] as int, m['to'] as int);
        case 'remove':
          game.remove(m['p'] as int);
      }
    });
  }

  bool get _canAct {
    if (game.isOver) return false;
    return switch (widget.setup.kind) {
      PlayKind.local => true,
      PlayKind.ai => game.turn == me && !_aiThinking,
      PlayKind.online => game.turn == me,
    };
  }

  void _tap(int p) {
    if (!_canAct) return;
    if (game.mustRemove) {
      if (game.remove(p)) {
        widget.setup.send({'t': 'remove', 'p': p});
        _after();
      }
      return;
    }
    if (game.phaseOf(game.turn) == MillPhase.placing) {
      if (game.place(p)) {
        Sound.play(Sfx.place);
        widget.setup.send({'t': 'place', 'p': p});
        _after();
      }
      return;
    }
    final s = selected;
    if (s != null && game.targets(s).contains(p)) {
      game.move(s, p);
      Sound.play(Sfx.place);
      widget.setup.send({'t': 'move', 'from': s, 'to': p});
      _after();
      return;
    }
    setState(() => selected = game.board[p] == game.turn ? p : null);
  }

  void _after() {
    setState(() => selected = null);
    _maybeAi();
  }

  Future<void> _maybeAi() async {
    if (widget.setup.kind != PlayKind.ai || game.isOver || game.turn == me) {
      return;
    }
    setState(() => _aiThinking = true);
    while (mounted && !game.isOver && game.turn != me) {
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      final a = game.aiAction();
      if (a == null) break;
      Sound.play(Sfx.place);
      setState(() {
        switch (a.$1) {
          case 'place':
            game.place(a.$2);
          case 'move':
            game.move(a.$2, a.$3);
          default:
            game.remove(a.$2);
        }
      });
    }
    if (mounted) setState(() => _aiThinking = false);
  }

  void _reset({bool send = true}) {
    setState(() {
      game = MillGame();
      round++;
      selected = null;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    _maybeAi();
  }

  String _name(int p) => switch (widget.setup.kind) {
    PlayKind.local => p == 1 ? 'Weiß' : 'Schwarz',
    PlayKind.ai => p == me ? 'Du' : 'Computer',
    PlayKind.online => p == me ? 'Du' : widget.setup.opponentName,
  };

  List<int> _winnerSeats() {
    if (game.winner == 0) return [0, 1];
    final whiteSeat = round.isEven ? 0 : 1;
    return [game.winner == 1 ? whiteSeat : 1 - whiteSeat];
  }

  String _status() {
    if (game.draw) return 'Remis';
    if (game.winner != 0) {
      final n = _name(game.winner);
      return n == 'Du' ? 'Du hast gewonnen! 🎉' : '$n gewinnt!';
    }
    final n = _name(game.turn);
    final you = n == 'Du';
    if (game.mustRemove) {
      return you
          ? 'Mühle! Nimm einen gegnerischen Stein'
          : '$n hat eine Mühle!';
    }
    final left = game.toPlace[game.turn];
    if (game.phaseOf(game.turn) == MillPhase.placing) {
      return you ? 'Setze einen Stein (noch $left)' : '$n setzt (noch $left)';
    }
    if (game.canFly(game.turn)) {
      return you ? 'Springe mit einem Stein' : '$n springt';
    }
    return you ? 'Ziehe einen Stein' : '$n zieht';
  }

  @override
  Widget build(BuildContext context) {
    final targets = selected == null ? const <int>[] : game.targets(selected!);
    final removable = game.mustRemove && _canAct
        ? game.removable()
        : const <int>[];
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Mühle',
      child: Column(
        children: [
          TurnBanner(text: _status(), highlight: _canAct || game.isOver),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [_stoneInfo(1), _stoneInfo(2)],
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final unit = box.maxWidth / 7;
                      Offset at(int i) =>
                          (pointPosition(i) + const Offset(0.5, 0.5)) * unit;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _BoardPainter(unit)),
                          ),
                          for (var i = 0; i < 24; i++)
                            Positioned(
                              left: at(i).dx - unit * 0.45,
                              top: at(i).dy - unit * 0.45,
                              width: unit * 0.9,
                              height: unit * 0.9,
                              child: GestureDetector(
                                key: ValueKey('mill$i'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _tap(i),
                                child: _stone(
                                  i,
                                  targets.contains(i),
                                  removable.contains(i),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (game.isOver)
            GameOverActions(
              setup: widget.setup,
              winnerSeats: _winnerSeats(),
              onRematch: _reset,
            ),
        ],
      ),
    );
  }

  Widget _stoneInfo(int p) => Chip(
    avatar: CircleAvatar(
      backgroundColor: p == 1 ? Colors.white : Colors.black,
      radius: 8,
    ),
    label: Text(
      '${_name(p)}: ${game.stones(p)}'
      '${game.toPlace[p] > 0 ? ' (+${game.toPlace[p]})' : ''}',
    ),
  );

  Widget _stone(int i, bool target, bool removable) {
    final v = game.board[i];
    final last = game.lastMove;
    final isLast = last != null && last.$2 == i;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: v == 0 ? (target ? 18 : 10) : double.infinity,
        height: v == 0 ? (target ? 18 : 10) : double.infinity,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: v == 0
              ? (target ? Colors.green : const Color(0xFF4E342E))
              : v == 1
              ? const Color(0xFFFAFAFA)
              : const Color(0xFF212121),
          border: v == 0
              ? null
              : Border.all(
                  color: removable
                      ? Colors.red
                      : selected == i
                      ? Colors.greenAccent
                      : isLast
                      ? Colors.amber
                      : Colors.black54,
                  width: removable || selected == i || isLast ? 4 : 1.5,
                ),
          boxShadow: v == 0
              ? null
              : const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 3,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.unit);
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xFFE0B97A),
    );
    final line = Paint()
      ..color = const Color(0xFF4E342E)
      ..strokeWidth = 3;
    Offset at(int i) => (pointPosition(i) + const Offset(0.5, 0.5)) * unit;
    for (var i = 0; i < 24; i++) {
      for (final n in MillGame.neighbours[i]) {
        if (n > i) canvas.drawLine(at(i), at(n), line);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.unit != unit;
}
