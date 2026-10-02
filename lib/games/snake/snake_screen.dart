import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/sound.dart';
import '../../ui/leaderboard_screen.dart';
import 'snake_logic.dart';

class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen>
    with SingleTickerProviderStateMixin {
  SnakeGame game = SnakeGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;
  bool running = false;
  bool wrap = false;
  int best = 0;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => best = p.getInt('snake.best') ?? 0);
      Leaderboard.best('snake').then((b) {
        if (mounted && b != null && b > best) setState(() => best = b);
      });
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!running || game.dead) return;
    _acc += dt;
    final interval = 1 / game.speed;
    var changed = false;
    while (_acc >= interval && !game.dead) {
      _acc -= interval;
      final before = game.score;
      game.step();
      if (game.score > before) {
        HapticFeedback.selectionClick();
        Sound.play(Sfx.eat);
      }
      changed = true;
    }
    if (game.dead) _gameOver();
    if (changed) setState(() {});
  }

  Future<void> _gameOver() async {
    running = false;
    HapticFeedback.heavyImpact();
    Sound.play(Sfx.fall);
    if (game.score > 0) await Leaderboard.submit('snake', game.score);
    if (game.score > best) best = game.score;
    if (mounted) setState(() {});
  }

  void _start() {
    setState(() {
      game = SnakeGame(wrap: wrap);
      running = true;
      _acc = 0;
    });
    _focus.requestFocus();
  }

  void _swipe(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (v.distance < 50) return;
    if (v.dx.abs() > v.dy.abs()) {
      game.turn(v.dx > 0 ? Dir.right : Dir.left);
    } else {
      game.turn(v.dy > 0 ? Dir.down : Dir.up);
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final d = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowUp => Dir.up,
      LogicalKeyboardKey.arrowDown => Dir.down,
      LogicalKeyboardKey.arrowLeft => Dir.left,
      LogicalKeyboardKey.arrowRight => Dir.right,
      _ => null,
    };
    if (d == null) return KeyEventResult.ignored;
    game.turn(d);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B2A1B),
      appBar: AppBar(
        title: const Text('Snake'),
        actions: [
          const LeaderboardButton(game: 'snake'),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('Punkte: ${game.score}   Rekord: $best'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanEnd: _swipe,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: game.width / game.height,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: wrap
                                ? Colors.lightGreen.shade800
                                : Colors.lightGreen,
                            width: 3,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(painter: _SnakePainter(game)),
                            ),
                            if (!running)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Center(child: _menu()),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Wischen zum Lenken',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            game.dead ? 'Game Over – ${game.score} Punkte' : 'Snake',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Durch Wände gehen'),
            value: wrap,
            onChanged: (v) => setState(() => wrap = v),
          ),
          FilledButton.icon(
            key: const ValueKey('snakeStart'),
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(game.dead ? 'Nochmal' : 'Start'),
          ),
        ],
      ),
    ),
  );
}

class _SnakePainter extends CustomPainter {
  _SnakePainter(this.game);
  final SnakeGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / game.width, ch = size.height / game.height;
    final grid = Paint()..color = const Color(0xFF223322);
    for (var y = 0; y < game.height; y++) {
      for (var x = 0; x < game.width; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw, ch), grid);
        }
      }
    }
    final (fx, fy) = game.food;
    canvas.drawCircle(
      Offset((fx + 0.5) * cw, (fy + 0.5) * ch),
      cw * 0.4,
      Paint()..color = Colors.redAccent,
    );
    for (var i = game.body.length - 1; i >= 0; i--) {
      final (x, y) = game.body[i];
      final t = i / game.body.length;
      final color = Color.lerp(
        const Color(0xFF76FF03),
        const Color(0xFF2E7D32),
        t,
      )!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * cw + 1, y * ch + 1, cw - 2, ch - 2),
          Radius.circular(cw * 0.3),
        ),
        Paint()..color = game.dead && i == 0 ? Colors.red : color,
      );
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}
