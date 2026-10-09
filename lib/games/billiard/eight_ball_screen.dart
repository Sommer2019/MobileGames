import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/net/room.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../ui/play_setup.dart';
import 'billiard_logic.dart';
import 'billiard_controls.dart';

/// 8-ball for two players, on one device or online.
///
/// Online the shooter's device is authoritative: it sends the shot (so the
/// opponent sees it animated) and afterwards the resulting ball positions
/// and events, which both devices then apply identically.
class EightBallScreen extends StatefulWidget {
  const EightBallScreen({super.key, required this.setup});
  final PlaySetup setup;

  @override
  State<EightBallScreen> createState() => _EightBallScreenState();
}

class _EightBallScreenState extends State<EightBallScreen>
    with
        SingleTickerProviderStateMixin,
        SavedGameState,
        GameMirror,
        SavedGameMirror {
  @override
  String? get mirrorGame => widget.setup.online ? null : 'billiard';

  @override
  Map<String, dynamic> get mirrorSetup => widget.setup.mirrorInfo;

  BilliardGame game = BilliardGame();
  EightBallRules rules = EightBallRules();
  late int round = widget.setup.firstRound;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double aimAngle = 0;
  double power = 0;
  Offset spin = Offset.zero;
  StreamSubscription<RoomMessage>? _sub;

  bool _myShotRunning = false;

  /// The computer is planning or aiming its shot.
  bool _botBusy = false;
  final EightBallAi _ai = EightBallAi();
  bool _clearedBefore = false;
  bool _remoteShotRunning = false;
  Map<String, dynamic>? _pendingSettle;

  /// Player index p is played by seat (p + round) % 2.
  int get myIndex => (widget.setup.mySeat - round % 2 + 2) % 2;

  int _seatOf(int p) => (p + round) % 2;

  /// The computer has to shoot now (on this device).
  bool get _botTurn {
    final seat = _seatOf(rules.current);
    return !rules.isOver &&
        widget.setup.isBot(seat) &&
        widget.setup.controls(seat);
  }

  /// The table right before the running shot (a shot left half-way is
  /// taken back).
  Map<String, dynamic>? _beforeShot;

  Map<String, dynamic> get _state => {
    'round': round,
    'game': game.toJson(),
    'rules': rules.toJson(),
  };

  @override
  String? get saveKey => widget.setup.saveKey('eight_ball');

  @override
  Map<String, dynamic>? saveGame() {
    if (game.moving && _beforeShot != null) return _beforeShot;
    if (rules.isOver || game.shots == 0) return null;
    return _state;
  }

  /// The running shot (for watching friends): its start and the stroke.
  Map<String, dynamic>? _lastShot;

  @override
  Map<String, dynamic>? mirrorState() {
    final moving = game.moving && _beforeShot != null && _lastShot != null;
    return {
      ...(moving ? _beforeShot! : _state),
      'shot': moving ? _lastShot : null,
    };
  }

  /// A friend's shot is animated here from the same start.
  @override
  void applyMirror(Map<String, dynamic> state) {
    final shot = state['shot'] as Map<String, dynamic>?;
    if (shot == null) {
      _beforeShot = null;
      _lastShot = null;
      restoreGame(state);
      return;
    }
    if (_lastShot?['n'] == shot['n']) return; // already rolling
    restoreGame(state);
    _beforeShot = Map<String, dynamic>.from(state)..remove('shot');
    _lastShot = shot;
    game.shoot(
      (shot['a'] as num).toDouble(),
      (shot['p'] as num).toDouble(),
      spinX: (shot['sx'] as num).toDouble(),
      spinY: (shot['sy'] as num).toDouble(),
    );
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    round = data['round'] as int;
    rules = EightBallRules.fromJson(data['rules'] as Map<String, dynamic>);
    game.load(data['game'] as Map<String, dynamic>);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _ticker = createTicker(_tick)..start();
    _sub = widget.setup.listen((m) => _onMessage(m.data));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  /// A shot result that arrived (or was replayed) before the next shot:
  /// apply it right away, so earlier shots need no animation.
  void _applyPendingSettle() {
    final settle = _pendingSettle;
    if (settle == null) return;
    _pendingSettle = null;
    _remoteShotRunning = false;
    game.restore(settle['snap'] as List<dynamic>);
    rules.evaluate(
      pocketed: [for (final n in settle['pocketed'] as List) n as int],
      firstHit: settle['firstHit'] as int?,
      scratched: settle['scratched'] as bool? ?? false,
      clearedBefore: settle['cleared'] as bool? ?? false,
    );
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'cue':
        _applyPendingSettle();
        setState(() {
          final cx = m['cx'], cy = m['cy'];
          if (cx is num && cy is num) {
            game.cue
              ..x = cx.toDouble()
              ..y = cy.toDouble();
          }
          game.shoot(
            (m['angle'] as num).toDouble(),
            (m['power'] as num).toDouble(),
            spinX: (m['sx'] as num?)?.toDouble() ?? 0,
            spinY: (m['sy'] as num?)?.toDouble() ?? 0,
          );
          _remoteShotRunning = true;
        });
      case 'place':
        _applyPendingSettle();
        setState(() {
          game.placeCue((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
        });
      case 'settle':
        _pendingSettle = m;
      case 'rematch':
        _applyPendingSettle();
        _reset(send: false);
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    if (game.moving) {
      final before = game.balls.where((b) => b.pocketed).length;
      setState(() => game.step(min(dt, 0.05)));
      playTableSounds(game);
      if (game.balls.where((b) => b.pocketed).length > before) {
        HapticFeedback.lightImpact();
      }
      return;
    }
    if (_myShotRunning) {
      _myShotRunning = false;
      _beforeShot = null;
      final pocketed = List<int>.from(game.pocketedThisShot);
      setState(() {
        rules.evaluate(
          pocketed: pocketed,
          firstHit: game.firstHit,
          scratched: game.scratched,
          clearedBefore: _clearedBefore,
        );
      });
      widget.setup.send({
        't': 'settle',
        'snap': game.snapshot(),
        'pocketed': pocketed,
        'firstHit': game.firstHit,
        'scratched': game.scratched,
        'cleared': _clearedBefore,
      });
    }
    if (_botTurn && !_botBusy && _pendingSettle == null) _botShot();
    final settle = _pendingSettle;
    if (settle != null) {
      _pendingSettle = null;
      _remoteShotRunning = false;
      setState(() {
        game.restore(settle['snap'] as List<dynamic>);
        rules.evaluate(
          pocketed: [for (final n in settle['pocketed'] as List) n as int],
          firstHit: settle['firstHit'] as int?,
          scratched: settle['scratched'] as bool? ?? false,
          clearedBefore: settle['cleared'] as bool? ?? false,
        );
      });
    }
  }

  bool get _canShoot => _tableReady && !_botTurn;

  bool get _tableReady =>
      !game.moving &&
      !rules.isOver &&
      !_myShotRunning &&
      !_remoteShotRunning &&
      _pendingSettle == null &&
      (!widget.setup.online || rules.current == myIndex);

  void _shoot(double p) {
    if (!_canShoot) return;
    _fire(p);
  }

  /// The computer looks at the table, turns the cue towards its target
  /// and shoots.
  Future<void> _botShot() async {
    _botBusy = true;
    final plan = _ai.plan(game.toJson(), rules);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || !_botTurn) return _botDone();
    if (plan.cueX != null) _placeCueFor(plan.cueX!, plan.cueY!);
    // Turn the cue smoothly (the short way round).
    final from = aimAngle;
    var delta = (plan.angle - from) % (2 * pi);
    if (delta > pi) delta -= 2 * pi;
    for (var i = 1; i <= 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      if (!mounted) return;
      setState(() => aimAngle = from + delta * i / 20);
    }
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      setState(() => power = plan.power * i / 10);
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_tableReady || !_botTurn) return _botDone();
    setState(() {
      aimAngle = plan.angle;
      power = 0;
      spin = Offset.zero;
    });
    _fire(plan.power);
    _botDone();
  }

  void _botDone() => _botBusy = false;

  void _fire(double p) {
    if (!_tableReady || p <= 0.02) return;
    final group = rules.groups[rules.current];
    _clearedBefore =
        group != null && rules.remainingOf(game, rules.current) == 0;
    final cx = game.cue.x, cy = game.cue.y;
    _beforeShot = _state;
    if (game.shoot(aimAngle, p, spinX: spin.dx, spinY: spin.dy)) {
      _lastShot = {
        'a': aimAngle,
        'p': p,
        'sx': spin.dx,
        'sy': spin.dy,
        'n': game.shots,
      };
      _myShotRunning = true;
      widget.setup.send({
        't': 'cue',
        'angle': aimAngle,
        'power': p,
        'cx': cx,
        'cy': cy,
        'sx': spin.dx,
        'sy': spin.dy,
      });
    }
  }

  void _placeCue(double x, double y) {
    if (!_canShoot) return;
    _placeCueFor(x, y);
  }

  void _placeCueFor(double x, double y) {
    if (game.placeCue(x, y)) {
      setState(() {});
      widget.setup.send({'t': 'place', 'x': x, 'y': y});
    }
  }

  void _reset({bool send = true, bool swap = true}) {
    setState(() {
      _beforeShot = null;
      game = BilliardGame();
      rules = EightBallRules();
      if (swap) round++;
      _myShotRunning = false;
      _remoteShotRunning = false;
      _pendingSettle = null;
    });
    if (send) widget.setup.send({'t': 'rematch'});
    persistGame();
  }

  String _name(int p) {
    final room = widget.setup.room;
    if (room != null) return p == myIndex ? 'Du' : room.names[(p + round) % 2];
    if (widget.setup.botSeats.isNotEmpty) {
      return widget.setup.seatName(_seatOf(p));
    }
    return 'Spieler ${p + 1}';
  }

  String _groupLabel(BallGroup? g) => switch (g) {
    BallGroup.solids => 'Volle (1–7)',
    BallGroup.stripes => 'Halbe (9–15)',
    null => 'offen',
  };

  String _status() {
    if (rules.isOver) {
      final w = _name(rules.winner!);
      return w == 'Du' ? 'Du hast gewonnen! 🎱' : '$w gewinnt!';
    }
    final n = _name(rules.current);
    if (_botTurn) return '$n zielt …';
    return n == 'Du' ? 'Du bist am Stoß' : '$n ist am Stoß';
  }

  @override
  Widget build(BuildContext context) {
    return OnlineGameFrame(
      setup: widget.setup,
      title: '8-Ball',
      actions: [
        if (saveKey != null)
          RestartButton(onRestart: () => _reset(send: false, swap: false)),
      ],
      child: Row(
        children: [
          Expanded(
            child: PoolTable(
              game: game,
              aimAngle: aimAngle,
              power: power,
              enabled: _canShoot,
              onAim: (a) => setState(() => aimAngle = a),
              onPlaceCue: _placeCue,
              spin: spin,
            ),
          ),
          SizedBox(
            width: 150,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Text(_status(), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                if (rules.lastEvent.isNotEmpty)
                  Text(
                    rules.lastEvent,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                for (var p = 0; p < 2; p++)
                  Card(
                    color: p == rules.current && !rules.isOver
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name(p),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(_groupLabel(rules.groups[p])),
                          if (rules.groups[p] != null)
                            Text(
                              rules.remainingOf(game, p) == 0
                                  ? 'Jetzt die 8!'
                                  : 'Noch ${rules.remainingOf(game, p)}',
                            ),
                        ],
                      ),
                    ),
                  ),
                if (rules.isOver)
                  GameOverActions(
                    setup: widget.setup,
                    winnerSeats: [(rules.winner! + round) % 2],
                    onRematch: _reset,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: CueControls(
                  enabled: _canShoot,
                  onPower: (p) => setState(() => power = p),
                  onShoot: _shoot,
                  onRotate: (d) => setState(() => aimAngle += d),
                  spin: spin,
                  onSpin: (v) => setState(() => spin = v),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
