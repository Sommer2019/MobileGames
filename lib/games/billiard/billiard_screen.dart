import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import 'billiard_controls.dart';
import 'billiard_logic.dart';

class BilliardScreen extends StatefulWidget {
  const BilliardScreen({super.key});

  @override
  State<BilliardScreen> createState() => _BilliardScreenState();
}

class _BilliardScreenState extends State<BilliardScreen>
    with SingleTickerProviderStateMixin, SavedGameState, GameMirror {
  final BilliardGame game = BilliardGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double aimAngle = 0; // pointing at the rack from the head spot
  double power = 0;
  Offset spin = Offset.zero;
  int? best;
  bool _wonShown = false;
  SoloMode mode = SoloMode.eightLast;
  late SoloRules rules = SoloRules(mode);
  bool _shotRunning = false;
  int _othersBefore = 0;
  int? _targetBefore;

  int get score => game.score + rules.penalties;

  /// A game is running: shots were played and it isn't decided yet.
  bool get _inGame => game.shots > 0 && !game.won && !rules.lost;
  String get _bestKey => 'billiard.best.${mode.name}';

  /// The table right before the running shot (a shot left half-way is
  /// taken back).
  Map<String, dynamic>? _beforeShot;

  @override
  String get saveKey => 'billiard';

  @override
  Map<String, dynamic>? saveGame() {
    if (game.moving && _beforeShot != null) return _beforeShot;
    if (!_inGame) return null;
    return {'game': game.toJson(), 'rules': rules.toJson()};
  }

  /// The running shot (for watching friends).
  Map<String, dynamic>? _lastShot;

  @override
  String? get mirrorGame => 'billiard';

  @override
  Map<String, dynamic> get mirrorSetup => const {'players': 1};

  @override
  Map<String, dynamic>? mirrorState() {
    final moving = game.moving && _beforeShot != null && _lastShot != null;
    return {
      ...(moving
          ? _beforeShot!
          : {'game': game.toJson(), 'rules': rules.toJson()}),
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
    if (_lastShot?['n'] == shot['n']) return;
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
    rules = SoloRules.fromJson(data['rules'] as Map<String, dynamic>);
    mode = rules.mode;
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
    _loadBest();
  }

  void _loadBest() {
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => best = p.getInt(_bestKey));
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
    playTableSounds(game);
    if (game.balls.where((b) => b.pocketed).length > pocketedBefore) {
      HapticFeedback.lightImpact();
    }
    if (!game.moving && _shotRunning) {
      _shotRunning = false;
      _beforeShot = null;
      setState(() {
        rules.evaluate(
          pocketed: List<int>.from(game.pocketedThisShot),
          firstHit: game.firstHit,
          scratched: game.scratched,
          othersBefore: _othersBefore,
          targetBefore: _targetBefore,
        );
      });
      if (rules.lost) {
        _lost();
      } else if (game.won && !_wonShown) {
        _wonShown = true;
        _finish();
      }
    }
  }

  void _shoot(double angle, double power) {
    if (rules.lost) return;
    _beforeShot = {'game': game.toJson(), 'rules': rules.toJson()};
    _othersBefore = SoloRules.othersLeft(game);
    _targetBefore = rules.target(game);
    if (game.shoot(angle, power, spinX: spin.dx, spinY: spin.dy)) {
      _shotRunning = true;
      _lastShot = {
        'a': angle,
        'p': power,
        'sx': spin.dx,
        'sy': spin.dy,
        'n': game.shots,
      };
    }
  }

  Future<void> _lost() async {
    HapticFeedback.heavyImpact();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Verloren 🎱'),
        content: Text(rules.lastEvent),
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

  Future<void> _finish() async {
    await Leaderboard.submit('billiard.${mode.name}', score);
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getInt(_bestKey);
    if (prev == null || score < prev) {
      await prefs.setInt(_bestKey, score);
      best = score;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tisch abgeräumt! 🎱'),
        content: Text(
          '${game.shots} Stöße, ${game.fouls + rules.penalties} Fouls → '
          '$score Punkte\n(weniger ist besser, Bestwert: ${best ?? score})',
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
    _beforeShot = null;
    game.rack();
    rules = SoloRules(mode);
    _wonShown = false;
    _shotRunning = false;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF263238),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: PoolTable(
                game: game,
                aimAngle: aimAngle,
                power: power,
                enabled: !game.moving && !rules.lost && !game.won,
                highlight: rules.target(game),
                spin: spin,
                onAim: (a) => setState(() => aimAngle = a),
                onPlaceCue: (x, y) => setState(() => game.placeCue(x, y)),
              ),
            ),
            SizedBox(
              width: 150,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Zurück',
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
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                        RestartButton(color: Colors.white, onRestart: _restart),
                      ],
                    ),
                    // During a game only the mode being played is shown.
                    for (final m in SoloMode.values)
                      if (!_inGame || m == mode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(
                              m.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: mode == m,
                            onSelected: _inGame
                                ? null
                                : (_) {
                                    mode = m;
                                    _restart();
                                    _loadBest();
                                  },
                          ),
                        ),
                    const SizedBox(height: 4),
                    _stat('Stöße', '${game.shots}'),
                    _stat('Fouls', '${game.fouls + rules.penalties}'),
                    if (rules.target(game) != null)
                      _stat('Ziel', '${rules.target(game)}'),
                    _stat('Übrig', '${game.remaining}'),
                    if (best != null) _stat('Bestwert', '$best'),
                    if (rules.lastEvent.isNotEmpty)
                      Text(
                        rules.lastEvent,
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      game.cueInHand
                          ? 'Weiße verschieben: Kugel ziehen'
                          : 'Tisch antippen zum Zielen',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CueControls(
                    enabled: !game.moving && !rules.lost && !game.won,
                    onPower: (p) => setState(() => power = p),
                    onShoot: (p) => _shoot(aimAngle, p),
                    onRotate: (d) => setState(() => aimAngle += d),
                    spin: spin,
                    onSpin: (v) => setState(() => spin = v),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}
