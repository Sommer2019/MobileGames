import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billiard_logic.dart';

const _ballColors = {
  1: Color(0xFFFDD835),
  2: Color(0xFF1E88E5),
  3: Color(0xFFE53935),
  4: Color(0xFF8E24AA),
  5: Color(0xFFFB8C00),
  6: Color(0xFF43A047),
  7: Color(0xFF6D4C41),
  8: Color(0xFF212121),
};

Color ballColor(int n) =>
    n == 0 ? Colors.white : _ballColors[n > 8 ? n - 8 : n]!;

class BilliardScreen extends StatefulWidget {
  const BilliardScreen({super.key});

  @override
  State<BilliardScreen> createState() => _BilliardScreenState();
}

class _BilliardScreenState extends State<BilliardScreen>
    with SingleTickerProviderStateMixin {
  final BilliardGame game = BilliardGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Offset? _aimPoint; // in table units
  int? best;
  bool _wonShown = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _ticker = createTicker(_tick)..start();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => best = p.getInt('billiard.best'));
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || !game.moving) return;
    final pocketedBefore = game.balls.where((b) => b.pocketed).length;
    setState(() => game.step(min(dt, 0.05)));
    if (game.balls.where((b) => b.pocketed).length > pocketedBefore) {
      HapticFeedback.lightImpact();
    }
    if (!game.moving && game.won && !_wonShown) {
      _wonShown = true;
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt('billiard.best');
    if (prev == null || game.score < prev) {
      await prefs.setInt('billiard.best', game.score);
      best = game.score;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tisch abgeräumt! 🎱'),
        content: Text(
          '${game.shots} Stöße, ${game.fouls} Fouls → ${game.score} Punkte\n'
          '(weniger ist besser, Bestwert: ${best ?? game.score})',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              _restart();
            },
            child: const Text('Neues Spiel'),
          ),
        ],
      ),
    );
  }

  void _restart() => setState(() {
    game.rack();
    _wonShown = false;
    _aimPoint = null;
  });

  (double angle, double power)? get _shot {
    final p = _aimPoint;
    if (p == null) return null;
    final dx = game.cue.x - p.dx, dy = game.cue.y - p.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final power = ((dist - BilliardGame.radius * 2) / 0.6).clamp(0.0, 1.0);
    return (atan2(dy, dx), power);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF263238),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  const rail = 0.06;
                  final scale = min(
                    c.maxWidth / (BilliardGame.width + rail * 2),
                    c.maxHeight / (BilliardGame.height + rail * 2),
                  );
                  Offset toTable(Offset local) =>
                      Offset(local.dx / scale - rail, local.dy / scale - rail);
                  return Center(
                    child: SizedBox(
                      width: (BilliardGame.width + rail * 2) * scale,
                      height: (BilliardGame.height + rail * 2) * scale,
                      child: GestureDetector(
                        onPanStart: (d) {
                          if (!game.moving) {
                            setState(
                              () => _aimPoint = toTable(d.localPosition),
                            );
                          }
                        },
                        onPanUpdate: (d) {
                          if (!game.moving) {
                            setState(
                              () => _aimPoint = toTable(d.localPosition),
                            );
                          }
                        },
                        onPanEnd: (_) {
                          final s = _shot;
                          setState(() => _aimPoint = null);
                          if (s != null && s.$2 > 0.02) game.shoot(s.$1, s.$2);
                        },
                        child: CustomPaint(
                          painter: TablePainter(game, scale, rail, _shot),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 150,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Billard',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _stat('Stöße', '${game.shots}'),
                    _stat('Fouls', '${game.fouls}'),
                    _stat('Übrig', '${game.remaining}'),
                    if (best != null) _stat('Bestwert', '$best'),
                    const Spacer(),
                    if (_shot != null)
                      LinearProgressIndicator(
                        value: _shot!.$2,
                        minHeight: 10,
                        color: Colors.orange,
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ziehen zum Zielen,\nloslassen zum Stoßen',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _restart,
                      child: const Text(
                        'Neu aufbauen',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}

class TablePainter extends CustomPainter {
  TablePainter(this.game, this.scale, this.rail, this.shot);
  final BilliardGame game;
  final double scale;
  final double rail;
  final (double, double)? shot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(rail * scale),
      ),
      Paint()..color = const Color(0xFF5D4037),
    );
    canvas.translate(rail * scale, rail * scale);
    final felt = Rect.fromLTWH(
      0,
      0,
      BilliardGame.width * scale,
      BilliardGame.height * scale,
    );
    canvas.drawRect(felt, Paint()..color = const Color(0xFF1B7A3E));
    Offset p(double x, double y) => Offset(x * scale, y * scale);
    canvas.drawCircle(
      p(BilliardGame.width * 0.25, BilliardGame.height / 2),
      2,
      Paint()..color = Colors.white38,
    );
    canvas.drawLine(
      p(BilliardGame.width * 0.25, 0),
      p(BilliardGame.width * 0.25, BilliardGame.height),
      Paint()..color = Colors.white12,
    );
    for (final (x, y) in BilliardGame.pockets) {
      canvas.drawCircle(
        p(x, y),
        BilliardGame.pocketRadius * scale,
        Paint()..color = Colors.black,
      );
    }
    final r = BilliardGame.radius * scale;
    final s = shot;
    if (s != null && !game.moving && !game.cue.pocketed) {
      final (angle, power) = s;
      final c = p(game.cue.x, game.cue.y);
      final dir = Offset(cos(angle), sin(angle));
      canvas.drawLine(
        c,
        c + dir * (scale * 0.8),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 1.5,
      );
      final back = r + 6 + power * 60;
      canvas.drawLine(
        c - dir * back,
        c - dir * (back + scale * 0.9),
        Paint()
          ..color = const Color(0xFFD7B377)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final b in game.balls) {
      if (b.pocketed) continue;
      final c = p(b.x, b.y);
      canvas.drawCircle(
        c + const Offset(1.5, 2),
        r,
        Paint()..color = Colors.black38,
      );
      final color = ballColor(b.number);
      canvas.drawCircle(
        c,
        r,
        Paint()..color = b.number > 8 ? Colors.white : color,
      );
      if (b.number > 8) {
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 2, height: r * 1.1),
          Paint()..color = color,
        );
        canvas.restore();
      }
      if (b.number != 0) {
        canvas.drawCircle(c, r * 0.48, Paint()..color = Colors.white);
        final tp = TextPainter(
          text: TextSpan(
            text: '${b.number}',
            style: TextStyle(
              fontSize: r * 0.62,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
      canvas.drawCircle(
        c - Offset(r * 0.35, r * 0.35),
        r * 0.25,
        Paint()..color = Colors.white38,
      );
    }
  }

  @override
  bool shouldRepaint(TablePainter old) => true;
}
