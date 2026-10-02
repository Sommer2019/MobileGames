import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/net/room.dart';
import '../../core/sound.dart';
import '../../ui/play_setup.dart';
import 'darts_logic.dart';
import 'motion_throw.dart';

class DartsScreen extends StatefulWidget {
  const DartsScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<DartsScreen> createState() => _DartsScreenState();
}

class _DartsScreenState extends State<DartsScreen>
    with SingleTickerProviderStateMixin {
  DartsGame? game;
  DartsMode mode = DartsMode.x501;
  bool doubleOut = true;

  // Motion control: phone at the cheek, turn to aim, swing to throw.
  bool motion = false;
  bool invertX = false, invertY = false;
  _MotionPhase _phase = _MotionPhase.idle;
  int _countdown = 0;
  MotionAim? _motionAim;
  final List<StreamSubscription<Object?>> _sensorSubs = [];
  (double, double, double)? _gravity;
  DateTime? _lastGyro;
  Timer? _hapticTimer;
  int _hapticTick = 0;
  late int round = widget.setup.firstRound;
  StreamSubscription<RoomMessage>? _sub;
  late final Ticker _ticker;
  final Random _random = Random();
  double _time = 0;

  Offset? _aim; // board mm, while the finger is down
  final List<(Offset, DartHit)> _shown = [];
  int? _shownFor;
  String? _lastInfo;
  int? _best;

  int get players => widget.setup.players;

  /// Seat that plays player index [i]; the starting seat rotates.
  int seatOf(int i) => (i + round) % players;
  int get myIndex =>
      (widget.setup.mySeat - round % players + players) % players;

  bool get _waitingForConfig => game == null && !widget.setup.isHost;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _time = d.inMicroseconds / 1e6;
      if (_aim != null) setState(() {});
    })..start();
    _sub = widget.setup.listen((m) => _onMessage(m.data));
    _loadBest();
  }

  Future<void> _loadBest() async {
    if (players != 1) return;
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _best = p.getInt('darts.best.${mode.name}'));
  }

  @override
  void dispose() {
    _stopSensors();
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'config':
        setState(() {
          mode = DartsMode.values.byName(m['mode'] as String);
          doubleOut = m['doubleOut'] as bool? ?? true;
          round = m['round'] as int? ?? round;
          _startGame();
        });
      case 'throw':
        final g = game;
        if (g == null || g.current == myIndex) return;
        _apply(Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()));
    }
  }

  void _startGame() {
    game = DartsGame(players: players, mode: mode, doubleOut: doubleOut);
    _shown.clear();
    _lastInfo = null;
  }

  void _start() {
    setState(_startGame);
    widget.setup.send({
      't': 'config',
      'mode': mode.name,
      'doubleOut': doubleOut,
      'round': round,
    });
    _loadBest();
  }

  void _rematch() {
    setState(() {
      round++;
      game = null;
    });
    if (!widget.setup.online) _start();
  }

  bool get _canThrow {
    final g = game;
    if (g == null || g.isOver) return false;
    return !widget.setup.online || g.current == myIndex;
  }

  String _name(int i) {
    final room = widget.setup.room;
    if (room != null) return i == myIndex ? 'Du' : room.names[seatOf(i)];
    if (players == 1) return 'Du';
    return 'Spieler ${i + 1}';
  }

  /// Wobble of the hand while aiming (mm).
  Offset get _sway => Offset(
    sin(_time * 1.9) * 7 + sin(_time * 4.3) * 3,
    cos(_time * 2.4) * 7 + sin(_time * 3.1) * 3,
  );

  double _gauss() {
    final u1 = max(1e-9, _random.nextDouble()), u2 = _random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  // ------------------------------------------------------- motion control

  void _startSensors() {
    if (_sensorSubs.isNotEmpty) return;
    try {
      _sensorSubs.add(
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) => _gravity = (e.x, e.y, e.z), onError: (_) {}),
      );
      _sensorSubs.add(
        gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
            .listen((e) {
              final now = DateTime.now();
              final last = _lastGyro;
              _lastGyro = now;
              if (last == null || _phase != _MotionPhase.aiming) return;
              final dt = now.difference(last).inMicroseconds / 1e6;
              _motionAim?.addGyro(e.x, e.y, e.z, min(dt, 0.1));
            }, onError: (_) {}),
      );
      _sensorSubs.add(
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen((e) {
          if (_phase != _MotionPhase.aiming) return;
          final t = _motionAim?.addAcceleration(e.x, e.y, e.z);
          if (t != null) _motionThrow(t);
        }, onError: (_) {}),
      );
    } catch (_) {
      // No sensors (emulator): motion control is not available.
    }
  }

  void _stopSensors() {
    for (final s in _sensorSubs) {
      s.cancel();
    }
    _sensorSubs.clear();
    _hapticTimer?.cancel();
  }

  Future<void> _prepareMotionThrow() async {
    if (!_canThrow || _phase != _MotionPhase.idle) return;
    _startSensors();
    for (var i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() {
        _phase = _MotionPhase.countdown;
        _countdown = i;
      });
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (!mounted) return;
    final g = _gravity ?? (0.0, 9.81, 0.0);
    final aim = MotionAim(invertX: invertX, invertY: invertY)
      ..calibrate(g.$1, g.$2, g.$3);
    setState(() {
      _motionAim = aim;
      _phase = _MotionPhase.aiming;
      _lastGyro = null;
    });
    HapticFeedback.heavyImpact();
    // Vibration tells how close to the bull you aim, without looking.
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted || _phase != _MotionPhase.aiming) return;
      setState(() {});
      final (x, y) = aim.aim;
      final d = sqrt(x * x + y * y);
      _hapticTick++;
      if (d < 20) {
        HapticFeedback.mediumImpact();
      } else if (d < 60 && _hapticTick.isEven) {
        HapticFeedback.lightImpact();
      } else if (d < 120 && _hapticTick % 4 == 0) {
        HapticFeedback.selectionClick();
      }
    });
  }

  /// The current holding position aims at the bull again (e.g. when the
  /// aim drifted or you changed your stance).
  void _recalibrate() {
    final g = _gravity;
    final aim = _motionAim;
    if (g == null || aim == null) return;
    aim.calibrate(g.$1, g.$2, g.$3);
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  void _motionThrow((double, double, double) t) {
    _hapticTimer?.cancel();
    final (x, y, strength) = t;
    final landing = Offset(
      x + _gauss() * 5,
      y + MotionAim.heightError(strength) + _gauss() * 5,
    );
    setState(() => _phase = _MotionPhase.idle);
    HapticFeedback.heavyImpact();
    widget.setup.send({'t': 'throw', 'x': landing.dx, 'y': landing.dy});
    _apply(landing);
  }

  void _cancelMotion() {
    _hapticTimer?.cancel();
    setState(() => _phase = _MotionPhase.idle);
  }

  void _release() {
    final aim = _aim;
    if (aim == null || !_canThrow) return;
    final landing = aim + _sway + Offset(_gauss() * 5, _gauss() * 5);
    setState(() => _aim = null);
    widget.setup.send({'t': 'throw', 'x': landing.dx, 'y': landing.dy});
    _apply(landing);
  }

  void _apply(Offset landing) {
    final g = game!;
    final player = g.current;
    final hit = Board.score(landing.dx, landing.dy);
    HapticFeedback.lightImpact();
    Sound.play(hit.isMiss ? Sfx.click : Sfx.thud);
    setState(() {
      if (_shownFor != player || _shown.length >= 3) {
        _shown.clear();
        _shownFor = player;
      }
      _shown.add((landing, hit));
      g.throwDart(hit);
      if (g.lastTurnBust && g.dartsInTurn == 0) {
        _lastInfo = '${_name(player)}: überworfen!';
      } else {
        _lastInfo = '${_name(player)}: ${hit.label}';
      }
    });
    if (g.isOver) _finished();
  }

  Future<void> _finished() async {
    final g = game!;
    if (players != 1) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'darts.best.${mode.name}';
    final prev = prefs.getInt(key);
    final darts = g.states[0].darts;
    await Leaderboard.submit('darts.${mode.name}', darts);
    if (prev == null || darts < prev) {
      await prefs.setInt(key, darts);
      if (mounted) setState(() => _best = darts);
    }
  }

  String _status() {
    final g = game;
    if (g == null) {
      return _waitingForConfig
          ? 'Der Host wählt den Spielmodus …'
          : 'Spielmodus wählen';
    }
    if (g.isOver) {
      final w = _name(g.winner!);
      if (players == 1) return 'Geschafft mit ${g.states[0].darts} Darts! 🎯';
      return w == 'Du' ? 'Du hast gewonnen! 🎯' : '$w gewinnt!';
    }
    final n = _name(g.current);
    final target = g.mode == DartsMode.aroundTheClock
        ? ' – Ziel: ${g.targetOf(g.current) == 25 ? 'Bull' : g.targetOf(g.current)}'
        : '';
    final dart = 'Dart ${g.dartsInTurn + 1}/3';
    if (n == 'Du') return 'Du wirfst ($dart)$target';
    return '$n wirft ($dart)$target';
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    return OnlineGameFrame(
      setup: widget.setup,
      title: 'Darts',
      child: g == null
          ? _setupPanel()
          : LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth > box.maxHeight * 1.1;
                final board = _boardArea();
                final info = _infoPanel(g);
                return wide
                    ? Row(
                        children: [
                          Expanded(flex: 3, child: board),
                          Expanded(flex: 2, child: info),
                        ],
                      )
                    : Column(
                        children: [
                          TurnBanner(
                            text: _status(),
                            highlight: _canThrow || g.isOver,
                          ),
                          Expanded(child: board),
                          SizedBox(
                            height: min(260, box.maxHeight * 0.38),
                            child: info,
                          ),
                        ],
                      );
              },
            ),
    );
  }

  Widget _setupPanel() {
    if (_waitingForConfig) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status()),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.adjust, size: 72, color: Colors.redAccent),
        const SizedBox(height: 16),
        Text('Spielmodus', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SegmentedButton<DartsMode>(
          segments: [
            for (final m in DartsMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => setState(() => mode = s.first),
        ),
        if (mode != DartsMode.aroundTheClock)
          SwitchListTile(
            title: const Text('Double Out'),
            subtitle: const Text(
              'Zum Beenden muss ein Doppel getroffen werden',
            ),
            value: doubleOut,
            onChanged: (v) => setState(() => doubleOut = v),
          ),
        const SizedBox(height: 16),
        Text('Steuerung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.touch_app),
              label: Text('Touch'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.vibration),
              label: Text('Bewegung'),
            ),
          ],
          selected: {motion},
          onSelectionChanged: (v) => setState(() => motion = v.first),
        ),
        if (motion) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Handy wie einen Dart an die Wange halten (Bildschirm zum '
              'Gesicht). Nach dem Countdown durch Drehen und Kippen zielen – '
              'je näher am Bull, desto öfter vibriert es. Dann kräftig nach '
              'vorne ausholen. Zu schwach fällt tief, zu stark fliegt hoch.',
            ),
          ),
          SwitchListTile(
            title: const Text('Links/rechts umkehren'),
            value: invertX,
            onChanged: (v) => setState(() => invertX = v),
          ),
          SwitchListTile(
            title: const Text('Oben/unten umkehren'),
            value: invertY,
            onChanged: (v) => setState(() => invertY = v),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          players == 1
              ? 'Ziel: mit möglichst wenigen Darts fertig werden.'
              : '$players Spieler – wer zuerst fertig ist, gewinnt.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('dartsStart'),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Los geht\'s'),
        ),
        const SizedBox(height: 24),
        const Text(
          'So geht\'s: Finger auf die Scheibe legen und zielen – das Fadenkreuz '
          'wackelt wie eine echte Hand. Loslassen wirft den Dart.',
        ),
      ],
    );
  }

  Widget _boardArea() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, box) {
              final scale =
                  box.maxWidth / 2 / 225; // px per mm (225 mm board radius)
              final center = Offset(box.maxWidth / 2, box.maxHeight / 2);
              Offset toMm(Offset local) =>
                  (local - center - const Offset(0, 70)) / scale;
              if (motion) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BoardPainter(
                          scale: scale,
                          darts: _shown,
                          aim: _phase == _MotionPhase.aiming
                              ? Offset(_motionAim!.aim.$1, _motionAim!.aim.$2)
                              : null,
                        ),
                      ),
                    ),
                    Center(child: _motionOverlay()),
                  ],
                );
              }
              return GestureDetector(
                key: const ValueKey('dartBoard'),
                onPanStart: (d) {
                  if (_canThrow) setState(() => _aim = toMm(d.localPosition));
                },
                onPanUpdate: (d) {
                  if (_canThrow) setState(() => _aim = toMm(d.localPosition));
                },
                onPanEnd: (_) => _release(),
                onTapDown: (d) {
                  if (_canThrow) setState(() => _aim = toMm(d.localPosition));
                },
                onTapUp: (_) => _release(),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _BoardPainter(
                    scale: scale,
                    darts: _shown,
                    aim: _aim == null ? null : _aim! + _sway,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _motionOverlay() {
    switch (_phase) {
      case _MotionPhase.idle:
        if (!_canThrow) return const SizedBox.shrink();
        return FilledButton.icon(
          key: const ValueKey('prepareThrow'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          ),
          onPressed: _prepareMotionThrow,
          icon: const Icon(Icons.sports_handball),
          label: const Text('Wurf vorbereiten'),
        );
      case _MotionPhase.countdown:
        return Text(
          '$_countdown',
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 12)],
          ),
        );
      case _MotionPhase.aiming:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Zielen … und werfen!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                shadows: [Shadow(blurRadius: 8)],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: const ValueKey('recalibrate'),
                  onPressed: _recalibrate,
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('Neu ausrichten'),
                ),
                TextButton(
                  onPressed: _cancelMotion,
                  child: const Text('Abbrechen'),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _infoPanel(DartsGame g) {
    final wide =
        MediaQuery.of(context).size.width >
        MediaQuery.of(context).size.height * 1.1;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (wide) TurnBanner(text: _status(), highlight: _canThrow || g.isOver),
        if (_lastInfo != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _lastInfo!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [for (final (_, h) in _shown) Chip(label: Text(h.label))],
        ),
        for (var i = 0; i < players; i++)
          Card(
            color: i == g.current && !g.isOver
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(_name(i)),
              subtitle: Text(
                g.mode == DartsMode.aroundTheClock
                    ? 'Darts: ${g.states[i].darts}'
                    : 'Ø ${g.states[i].average.toStringAsFixed(1)} • Darts: ${g.states[i].darts}',
              ),
              trailing: Text(
                g.mode == DartsMode.aroundTheClock
                    ? (g.winner == i
                          ? '✓'
                          : 'Ziel ${g.targetOf(i) == 25 ? 'Bull' : g.targetOf(i)}')
                    : '${g.states[i].remaining}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
        if (players == 1 && _best != null)
          Text('Bestwert: $_best Darts', textAlign: TextAlign.center),
        if (g.isOver)
          GameOverActions(
            setup: widget.setup,
            winnerSeats: [seatOf(g.winner!)],
            onRematch: _rematch,
            rematchLabel: widget.setup.online ? null : 'Nochmal',
          ),
      ],
    );
  }
}

enum _MotionPhase { idle, countdown, aiming }

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.scale, required this.darts, required this.aim});
  final double scale;
  final List<(Offset, DartHit)> darts;
  final Offset? aim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, 225 * scale, Paint()..color = const Color(0xFF212121));
    const black = Color(0xFF1B1B1B), cream = Color(0xFFF3E5C3);
    const red = Color(0xFFD32F2F), green = Color(0xFF2E7D32);
    void ring(double r1, double r2, Color a, Color b) {
      for (var i = 0; i < 20; i++) {
        final start = (-90 - 9 + i * 18) * pi / 180;
        final path = Path()
          ..arcTo(
            Rect.fromCircle(center: c, radius: r2 * scale),
            start,
            18 * pi / 180,
            true,
          )
          ..arcTo(
            Rect.fromCircle(center: c, radius: r1 * scale),
            start + 18 * pi / 180,
            -18 * pi / 180,
            false,
          )
          ..close();
        canvas.drawPath(path, Paint()..color = i.isEven ? a : b);
      }
    }

    ring(Board.tripleOuter, Board.doubleInner, black, cream);
    ring(Board.doubleInner, Board.doubleOuter, red, green);
    ring(Board.bullOuter, Board.tripleInner, black, cream);
    ring(Board.tripleInner, Board.tripleOuter, red, green);
    canvas.drawCircle(c, Board.bullOuter * scale, Paint()..color = green);
    canvas.drawCircle(c, Board.bullInner * scale, Paint()..color = red);
    final wire = Paint()
      ..color = Colors.grey.shade500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final r in [
      Board.bullInner,
      Board.bullOuter,
      Board.tripleInner,
      Board.tripleOuter,
      Board.doubleInner,
      Board.doubleOuter,
    ]) {
      canvas.drawCircle(c, r * scale, wire);
    }
    for (var i = 0; i < 20; i++) {
      final a = (-90 + i * 18) * pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: '${Board.numbers[i]}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15 * scale * 1.6,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(cos(a), sin(a)) * 195 * scale;
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    for (final (pos, _) in darts) {
      final p = c + pos * scale;
      canvas.drawLine(
        p,
        p + const Offset(10, 14),
        Paint()
          ..color = Colors.blueGrey.shade200
          ..strokeWidth = 3,
      );
      canvas.drawCircle(p, 4, Paint()..color = Colors.amber);
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke,
      );
    }
    final a = aim;
    if (a != null) {
      final p = c + a * scale;
      final cross = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 2;
      canvas.drawCircle(p, 10, cross..style = PaintingStyle.stroke);
      canvas.drawLine(p - const Offset(16, 0), p + const Offset(16, 0), cross);
      canvas.drawLine(p - const Offset(0, 16), p + const Offset(0, 16), cross);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
