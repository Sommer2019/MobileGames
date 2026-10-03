import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/saved_games.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/leaderboard_screen.dart';
import 'snake_logic.dart';

class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen>
    with SingleTickerProviderStateMixin, SavedGameState {
  SnakeGame game = SnakeGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;
  bool running = false;
  bool wrap = false;
  int best = 0;
  final _focus = FocusNode();

  /// A round was interrupted (paused or left) and can be continued.
  bool paused = false;

  @override
  String get saveKey => 'snake';

  @override
  Map<String, dynamic>? saveGame() {
    if (game.dead || game.won || (!running && !paused)) return null;
    return game.toJson();
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    game = SnakeGame.fromJson(data);
    wrap = game.wrap;
    paused = true;
  }

  void _pause() => setState(() {
    running = false;
    paused = true;
  });

  void _resume() {
    setState(() {
      running = true;
      paused = false;
      _acc = 0;
    });
    _focus.requestFocus();
  }

  /// Leaving the app pauses the round.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: () {
      if (running && mounted) _pause();
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
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
    _lifecycle.dispose();
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
      paused = false;
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

  /// Secret retro mode: the look of an old Nokia display.
  bool get _nokia => Secrets.on(Secret.retro);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _nokia
          ? const Color(0xFF2B3326)
          : const Color(0xFF1B2A1B),
      appBar: AppBar(
        title: const Text('Snake'),
        actions: [
          const LeaderboardButton(game: 'snake'),
          if (running)
            IconButton(
              key: const ValueKey('snakePause'),
              tooltip: 'Pause',
              onPressed: _pause,
              icon: const Icon(Icons.pause),
            ),
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
                          color: _nokia ? _SnakePainter.lcd : null,
                          border: Border.all(
                            color: _nokia
                                ? _SnakePainter.pixel
                                : wrap
                                ? Colors.lightGreen.shade800
                                : Colors.lightGreen,
                            width: 3,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _SnakePainter(game, nokia: _nokia),
                              ),
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
            game.dead
                ? 'Game Over – ${game.score} Punkte'
                : paused
                ? 'Pause – ${game.score} Punkte'
                : 'Snake',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (paused) ...[
            FilledButton.icon(
              key: const ValueKey('snakeResume'),
              onPressed: _resume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Weiter'),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            title: const Text('Durch Wände gehen'),
            value: wrap,
            onChanged: (v) => setState(() => wrap = v),
          ),
          if (paused)
            OutlinedButton.icon(
              key: const ValueKey('snakeStart'),
              onPressed: _start,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Neu starten'),
            )
          else
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
  _SnakePainter(this.game, {this.nokia = false});
  final SnakeGame game;
  final bool nokia;

  /// Colours of the Nokia LCD.
  static const lcd = Color(0xFFC7F0D8);
  static const pixel = Color(0xFF43523D);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / game.width, ch = size.height / game.height;
    if (nokia) {
      _paintNokia(canvas, cw, ch);
      return;
    }
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

  /// Square blocks with small gaps, the food as a little cross.
  void _paintNokia(Canvas canvas, double cw, double ch) {
    final p = Paint()..color = pixel;
    final g = cw * 0.12;
    for (final (x, y) in game.body) {
      canvas.drawRect(
        Rect.fromLTWH(x * cw + g, y * ch + g, cw - 2 * g, ch - 2 * g),
        p,
      );
    }
    final (fx, fy) = game.food;
    final c = Offset((fx + 0.5) * cw, (fy + 0.5) * ch);
    canvas.drawRect(
      Rect.fromCenter(center: c, width: cw * 0.3, height: ch * 0.8),
      p,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c, width: cw * 0.8, height: ch * 0.3),
      p,
    );
    if (game.dead && game.body.isNotEmpty) {
      final (hx, hy) = game.body.first;
      canvas.drawRect(
        Rect.fromLTWH(hx * cw, hy * ch, cw, ch),
        Paint()
          ..color = pixel
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}
