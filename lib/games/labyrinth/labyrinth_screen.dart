import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/sphere.dart';
import '../../ui/leaderboard_screen.dart';
import 'konami.dart';
import 'labyrinth_logic.dart';

class LabyrinthLevelsScreen extends StatefulWidget {
  const LabyrinthLevelsScreen({super.key});

  @override
  State<LabyrinthLevelsScreen> createState() => _LabyrinthLevelsScreenState();
}

class _LabyrinthLevelsScreenState extends State<LabyrinthLevelsScreen> {
  Map<int, double> best = {};

  /// Secret cheat (Konami code): all levels, harmless holes.
  bool cheat = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setCheat(bool on) async {
    setState(() => cheat = on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('labyrinth.cheat', on);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      cheat = prefs.getBool('labyrinth.cheat') ?? false;
      best = {
        for (var i = 0; i < labyrinthLevels.length; i++)
          if (prefs.getDouble('labyrinth.best.$i') != null)
            i: prefs.getDouble('labyrinth.best.$i')!,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kugellabyrinth'),
        actions: const [LeaderboardButton(game: 'labyrinth')],
      ),
      body: KonamiDetector(
        onUnlocked: () {
          _setCheat(!cheat);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                cheat
                    ? '🎮 Cheat aktiv: alle Level frei, Löcher harmlos'
                    : 'Cheat aus',
              ),
            ),
          );
        },
        child: _list(),
      ),
    );
  }

  Widget _list() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (cheat)
          Card(
            color: Colors.amber.shade100,
            child: SwitchListTile(
              key: const ValueKey('cheatSwitch'),
              title: const Text('🎮 Cheat aktiv'),
              subtitle: const Text(
                'Alle Level frei, nur das Zielloch zählt. '
                'Zeiten werden nicht gespeichert.',
              ),
              value: cheat,
              onChanged: _setCheat,
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Neige dein Handy, um die Kugel ins grüne Zielloch zu rollen. '
            'Fällt sie in ein anderes Loch, geht es von vorne los.',
          ),
        ),
        for (var i = 0; i < labyrinthLevels.length; i++)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(labyrinthLevels[i].name),
              subtitle: Text(
                best[i] != null
                    ? 'Bestzeit: ${best[i]!.toStringAsFixed(1)} s'
                    : 'Noch nicht geschafft',
              ),
              enabled: cheat || i == 0 || best.containsKey(i - 1),
              trailing: Icon(
                best.containsKey(i) ? Icons.check_circle : Icons.play_arrow,
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LabyrinthScreen(levelIndex: i, cheat: cheat),
                  ),
                );
                _load();
              },
            ),
          ),
      ],
    );
  }
}

class LabyrinthScreen extends StatefulWidget {
  const LabyrinthScreen({
    super.key,
    required this.levelIndex,
    this.cheat = false,
  });
  final int levelIndex;

  /// Holes don't swallow the ball; results are not saved.
  final bool cheat;

  @override
  State<LabyrinthScreen> createState() => _LabyrinthScreenState();
}

class _LabyrinthScreenState extends State<LabyrinthScreen>
    with SingleTickerProviderStateMixin {
  late int levelIndex = widget.levelIndex;
  late LabyrinthGame game = LabyrinthGame(labyrinthLevels[levelIndex])
    ..ghost = widget.cheat;
  late final Ticker _ticker;
  StreamSubscription<AccelerometerEvent>? _accel;
  Duration _last = Duration.zero;
  double tiltX = 0, tiltY = 0;
  bool _sensorSeen = false;
  Offset? _dragStart;
  int falls = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _ticker = createTicker(_tick)..start();
    try {
      _accel =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ).listen((e) {
            _sensorSeen = true;
            // Android convention: x is positive when the left edge points down,
            // y is positive when the top edge points up.
            tiltX = (-e.x / 9.81).clamp(-1.0, 1.0);
            tiltY = (e.y / 9.81).clamp(-1.0, 1.0);
          }, onError: (_) {});
    } catch (_) {
      // No accelerometer (e.g. emulator): touch control is used instead.
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _ticker.dispose();
    _accel?.cancel();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    final before = game.state;
    game.step(min(dt, 0.05), tiltX, tiltY);
    if (before == BallState.rolling && game.state != BallState.rolling) {
      HapticFeedback.mediumImpact();
      if (game.state == BallState.fell) {
        falls++;
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(game.reset);
        });
      } else {
        _won();
      }
    }
    setState(() {});
  }

  Future<void> _won() async {
    if (!widget.cheat) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'labyrinth.best.$levelIndex';
      final prev = prefs.getDouble(key);
      if (prev == null || game.elapsed < prev) {
        await prefs.setDouble(key, game.elapsed);
      }
      final solved = [
        for (var i = 0; i < labyrinthLevels.length; i++)
          if (prefs.getDouble('labyrinth.best.$i') != null) i,
      ].length;
      await Leaderboard.submit('labyrinth', solved);
    }
    if (!mounted) return;
    final hasNext = levelIndex + 1 < labyrinthLevels.length;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Geschafft! 🎉'),
        content: Text(
          'Zeit: ${game.elapsed.toStringAsFixed(1)} s\nAbstürze: $falls',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() {
                game.reset();
                falls = 0;
              });
            },
            child: const Text('Nochmal'),
          ),
          if (hasNext)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() {
                  levelIndex++;
                  game = LabyrinthGame(labyrinthLevels[levelIndex])
                    ..ghost = widget.cheat;
                  falls = 0;
                });
              },
              child: const Text('Nächstes Level'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                Navigator.pop(context);
              },
              child: const Text('Fertig'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3E2723),
      appBar: AppBar(
        title: Text('Level ${levelIndex + 1}: ${game.level.name}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${game.elapsed.toStringAsFixed(1)} s'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: boardWidth / boardHeight,
                  child: GestureDetector(
                    // Fallback for devices without accelerometer: drag to tilt.
                    onPanStart: (d) => _dragStart = d.localPosition,
                    onPanUpdate: (d) {
                      if (_sensorSeen && !kDebugMode) return;
                      final s = _dragStart;
                      if (s == null) return;
                      tiltX = ((d.localPosition.dx - s.dx) / 120).clamp(
                        -1.0,
                        1.0,
                      );
                      tiltY = ((d.localPosition.dy - s.dy) / 120).clamp(
                        -1.0,
                        1.0,
                      );
                    },
                    onPanEnd: (_) {
                      if (_sensorSeen && !kDebugMode) return;
                      tiltX = 0;
                      tiltY = 0;
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CustomPaint(
                        painter: _BoardPainter(game),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!_sensorSeen)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Kein Bewegungssensor gefunden – ziehe mit dem Finger zum Kippen.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.game);
  final LabyrinthGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / boardWidth;
    final board = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, const Radius.circular(6)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE8C894), Color(0xFFD7B077)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(board),
    );
    if (!game.level.frame) {
      // Open edge: a dark shadow shows where the board ends.
      canvas.drawRRect(
        RRect.fromRectAndRadius(board, const Radius.circular(6)),
        Paint()
          ..color = const Color(0xAA3E2723)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    // Wood grain.
    final grain = Paint()
      ..color = const Color(0x18000000)
      ..strokeWidth = 1;
    for (var y = 6.0; y < size.height; y += 11) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + sin(y) * 4), grain);
    }
    final holePaint = Paint()..color = const Color(0xFF1B1B1B);
    for (final h in game.level.holes) {
      canvas.drawCircle(Offset(h.x * s, h.y * s), h.radius * s, holePaint);
    }
    final g = game.level.goal;
    canvas.drawCircle(
      Offset(g.x * s, g.y * s),
      g.radius * s * 1.35,
      Paint()..color = const Color(0xFF2E7D32),
    );
    canvas.drawCircle(Offset(g.x * s, g.y * s), g.radius * s, holePaint);
    final wallPaint = Paint()..color = const Color(0xFF6D4C41);
    final shadow = Paint()..color = const Color(0x55000000);
    for (final w in game.level.walls) {
      final r = Rect.fromLTRB(w.left * s, w.top * s, w.right * s, w.bottom * s);
      canvas.drawRect(r.shift(const Offset(1.5, 2)), shadow);
      canvas.drawRect(r, wallPaint);
    }
    final ball = Offset(game.x * s, game.y * s);
    final shrink = game.state == BallState.rolling ? 1.0 : 0.7;
    final rad = LabyrinthGame.radius * s * shrink;
    canvas.drawCircle(ball + const Offset(2, 3), rad, shadow);
    canvas.drawCircle(
      ball,
      rad,
      Paint()
        ..shader = RadialGradient(
          colors: const [Colors.white, Color(0xFF9E9E9E), Color(0xFF424242)],
          stops: const [0, 0.5, 1],
          center: const Alignment(-0.4, -0.4),
        ).createShader(Rect.fromCircle(center: ball, radius: rad)),
    );
    // Dots on six sides make the rolling visible.
    final o = game.orientation;
    final (bx, by, bz) = o.b;
    final dot = Paint()..color = const Color(0x99263238);
    for (final (x, y, z) in [
      (o.qx, o.qy, o.qz),
      (o.ax, o.ay, o.az),
      (bx, by, bz),
    ]) {
      for (final sign in const [1.0, -1.0]) {
        final spot = SphereOrientation.capPath(
          ball,
          rad,
          x * sign,
          y * sign,
          z * sign,
          0.32,
        );
        if (spot != null) canvas.drawPath(spot, dot);
      }
    }
    // Fixed reflection of the light on top.
    canvas.drawCircle(
      ball - Offset(rad * 0.35, rad * 0.35),
      rad * 0.22,
      Paint()..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
