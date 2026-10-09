import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/mirror.dart';
import '../../core/secrets.dart';
import '../../core/sound.dart';
import '../../ui/leaderboard_screen.dart';
import 'arrows_logic.dart';

/// An arrow on its way: out of the board, or bouncing back.
class _Flight {
  _Flight(this.arrow, this.start, this.distance, {required this.blocked});
  final int arrow;
  final Duration start;

  /// Cells the head moves (blocked: up to the obstacle).
  final double distance;
  final bool blocked;

  static const speed = 22.0; // cells per second

  double get seconds =>
      blocked ? 2 * (distance + 0.35) / speed * 1.6 : distance / speed;

  /// Offset along the path at [t] seconds after the start.
  double offset(double t) {
    if (!blocked) return min(t * speed, distance);
    final peak = distance + 0.35;
    final half = seconds / 2;
    return t < half ? peak * t / half : max(0, peak * (2 - t / half));
  }
}

class ArrowsScreen extends StatefulWidget {
  const ArrowsScreen({super.key, this.startLevel, this.difficulty});

  /// For tests; otherwise the level reached last time.
  final int? startLevel;

  /// For tests; otherwise the difficulty chosen last time.
  final ArrowsDifficulty? difficulty;

  @override
  State<ArrowsScreen> createState() => _ArrowsScreenState();
}

class _ArrowsScreenState extends State<ArrowsScreen>
    with SingleTickerProviderStateMixin, GameMirror {
  @override
  String? get mirrorGame => 'arrows';

  @override
  Map<String, dynamic>? mirrorState() => {
    'd': diff.name,
    'l': level,
    'h': game.hearts,
    'r': [
      for (var i = 0; i < game.removed.length; i++)
        if (game.removed[i]) i,
    ],
  };

  /// A friend's level: the same arrows fly out here.
  @override
  void applyMirror(Map<String, dynamic> state) {
    final d =
        ArrowsDifficulty.values.asNameMap()[state['d']] ??
        ArrowsDifficulty.easy;
    final l = state['l'] as int;
    final removed = {for (final i in state['r'] as List) i as int};
    if (d != diff ||
        l != level ||
        game.removed.where((r) => r).length > removed.length) {
      diff = d;
      level = l;
      _restart();
    }
    for (final i in removed) {
      if (i >= game.removed.length || game.removed[i]) continue;
      final (steps, _) = game.wayOut(i);
      game.removed[i] = true;
      _flights.add(
        _Flight(
          i,
          _now,
          steps + game.level.arrows[i].cells.length + 1.0,
          blocked: false,
        ),
      );
    }
    final hearts = state['h'] as int;
    if (hearts < game.hearts) Sound.play(Sfx.thud);
    game.hearts = hearts;
  }

  static const _difficultyKey = 'arrows.difficulty';
  static String _levelKey(ArrowsDifficulty d) => 'arrows.level.${d.name}';

  int level = 1;
  ArrowsDifficulty diff = ArrowsDifficulty.easy;
  int _hintsUsed = 0;
  late ArrowsGame game;
  late final Ticker _ticker = createTicker(_tick);
  Duration _now = Duration.zero;
  final List<_Flight> _flights = [];
  int? _hint;
  Duration? _hintUntil;

  /// Arrow that bumped into another one (drawn red for a moment).
  int? _bumped;

  @override
  void initState() {
    super.initState();
    level = widget.startLevel ?? 1;
    diff = widget.difficulty ?? ArrowsDifficulty.easy;
    _restart();
    if (widget.startLevel == null && !mirroring) _loadLevel();
    _ticker.start();
  }

  Future<void> _loadLevel() async {
    final prefs = await SharedPreferences.getInstance();
    // Progress from before there were difficulties counts for Leicht.
    final old = prefs.getInt('arrows.level');
    if (old != null) {
      await prefs.setInt(_levelKey(ArrowsDifficulty.easy), old);
      await prefs.remove('arrows.level');
    }
    final d =
        widget.difficulty ??
        ArrowsDifficulty.values.asNameMap()[prefs.getString(_difficultyKey)] ??
        ArrowsDifficulty.easy;
    final saved = prefs.getInt(_levelKey(d)) ?? 1;
    if (!mounted || (saved == level && d == diff)) return;
    setState(() {
      level = saved;
      diff = d;
      _restart();
    });
  }

  Future<void> _chooseDifficulty() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final picked = await showModalBottomSheet<ArrowsDifficulty>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in ArrowsDifficulty.values)
              ListTile(
                key: ValueKey('arrowsDiff-${d.name}'),
                selected: d == diff,
                leading: Icon(
                  d == diff
                      ? Icons.radio_button_checked
                      : Icons.circle_outlined,
                ),
                title: Text(d.label),
                subtitle: Text(
                  '${d.hearts} ${d.hearts == 1 ? 'Herz' : 'Herzen'} · '
                  '${d.hints == null ? 'Tipps frei' : '${d.hints} ${d.hints == 1 ? 'Tipp' : 'Tipps'}'}'
                  ' · bis ${d.maxWidth}×${d.maxHeight}',
                ),
                trailing: Text('Level ${prefs.getInt(_levelKey(d)) ?? 1}'),
                onTap: () => Navigator.pop(context, d),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == diff || !mounted) return;
    await prefs.setString(_difficultyKey, picked.name);
    setState(() {
      diff = picked;
      level = prefs.getInt(_levelKey(picked)) ?? 1;
      _restart();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    _now = now;
    final done = _flights
        .where((f) => (now - f.start).inMicroseconds / 1e6 >= f.seconds)
        .toList();
    if (done.isNotEmpty) {
      _flights.removeWhere(done.contains);
      if (done.any((f) => f.arrow == _bumped && f.blocked)) _bumped = null;
    }
    if (_hintUntil != null && now > _hintUntil!) {
      _hint = null;
      _hintUntil = null;
    }
    if (_flights.isNotEmpty || done.isNotEmpty || _hint != null) {
      setState(() {});
    }
  }

  void _tap(int i) {
    if (game.won || game.lost) return;
    if (_flights.any((f) => f.arrow == i)) return;
    final (steps, blocker) = game.wayOut(i);
    final out = game.tap(i);
    final a = game.level.arrows[i];
    if (out) {
      Sound.play(Sfx.click);
      // Until the tail has left the board.
      _flights.add(
        _Flight(i, _now, steps + a.cells.length + 1.0, blocked: false),
      );
      if (_hint == i) _hint = null;
      if (game.won) _won();
    } else {
      Sound.play(Sfx.thud);
      _bumped = i;
      _flights.add(_Flight(i, _now, steps.toDouble(), blocked: true));
      if (blocker != null && game.lost) {
        Future<void>.delayed(const Duration(milliseconds: 600), _lostDialog);
      }
    }
    setState(() {});
  }

  Future<void> _won() async {
    Sound.play(Sfx.win);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_levelKey(diff), level + 1);
    await Leaderboard.submit('arrows.${diff.name}', level);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Level $level geschafft! 🎉'),
        content: Text(
          game.hearts == 3
              ? 'Ohne Fehler – stark!'
              : 'Mit ${game.hearts} ${game.hearts == 1 ? 'Herz' : 'Herzen'} übrig.',
        ),
        actions: [
          FilledButton(
            key: const ValueKey('arrowsNext'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Nächstes Level'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      level++;
      _restart();
    });
  }

  Future<void> _lostDialog() async {
    if (!mounted) return;
    Sound.play(Sfx.lose);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Keine Herzen mehr'),
        content: const Text('Versuch es gleich noch einmal.'),
        actions: [
          FilledButton(
            key: const ValueKey('arrowsRetry'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Nochmal'),
          ),
        ],
      ),
    );
    if (mounted) setState(_restart);
  }

  void _restart() {
    game = ArrowsGame(ArrowsLevel.generate(level, diff), hearts: diff.hearts);
    _hintsUsed = 0;
    _flights.clear();
    _hint = null;
    _bumped = null;
  }

  int? get _hintsLeft => diff.hints == null ? null : diff.hints! - _hintsUsed;

  void _showHint() {
    if (_hintsLeft == 0 || _hint != null) return;
    final h = game.hint();
    if (h == null) return;
    setState(() {
      _hintsUsed++;
      _hint = h;
      _hintUntil = _now + const Duration(seconds: 2);
    });
  }

  /// Board position of the hinted arrow's head (for tests).
  @visibleForTesting
  Offset? get hintCell {
    final h = _hint;
    if (h == null) return null;
    final (x, y) = game.level.arrows[h].head;
    return Offset((x + 1) * _cell, (y + 1) * _cell);
  }

  /// Cell size of the last layout.
  double _cell = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = game.level.arrows.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pfeile'),
        actions: [
          Badge(
            isLabelVisible: _hintsLeft != null,
            label: Text('${_hintsLeft ?? ''}'),
            offset: const Offset(-4, 4),
            child: IconButton(
              key: const ValueKey('arrowsHint'),
              tooltip: 'Tipp',
              onPressed: _hintsLeft == 0 ? null : _showHint,
              icon: Icon(
                Icons.lightbulb,
                color: _hintsLeft == 0 ? null : Colors.amber.shade700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Level neu starten',
            onPressed: () => setState(_restart),
            icon: const Icon(Icons.restart_alt),
          ),
          LeaderboardButton(game: 'arrows', board: 'arrows.${diff.name}'),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          ActionChip(
            key: const ValueKey('arrowsDifficulty'),
            avatar: const Icon(Icons.tune, size: 18),
            label: Text(
              '${diff.label.toUpperCase()}  ▾',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _chooseDifficulty,
          ),
          Text(
            'Level $level',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var h = 0; h < diff.hearts; h++)
                AnimatedScale(
                  scale: h < game.hearts ? 1 : 0.7,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    h < game.hearts ? Icons.favorite : Icons.favorite_border,
                    color: const Color(0xFFC0392B),
                    size: 34,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: total == 0 ? 0 : 1 - game.left / total,
            minHeight: 6,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: (game.level.width + 1) / (game.level.height + 1),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final cell = box.maxWidth / (game.level.width + 1);
                      _cell = cell;
                      return GestureDetector(
                        key: const ValueKey('arrowsBoard'),
                        onTapUp: (d) {
                          final i = _arrowAt(d.localPosition, cell);
                          if (i != null) _tap(i);
                        },
                        child: CustomPaint(
                          size: box.biggest,
                          painter: _ArrowsPainter(
                            game: game,
                            cell: cell,
                            flights: _flights,
                            now: _now,
                            hint: _hint,
                            bumped: _bumped,
                            xray: Secrets.on(Secret.arrowsXray),
                            ink: scheme.onSurface,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Arrow under a tap: the one with a cell nearest to it.
  int? _arrowAt(Offset p, double cell) {
    int? best;
    var bestD = cell * 0.75;
    for (var i = 0; i < game.level.arrows.length; i++) {
      if (game.removed[i]) continue;
      for (final (x, y) in game.level.arrows[i].cells) {
        final d = (Offset((x + 1) * cell, (y + 1) * cell) - p).distance;
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    return best;
  }
}

class _ArrowsPainter extends CustomPainter {
  _ArrowsPainter({
    required this.game,
    required this.cell,
    required this.flights,
    required this.now,
    required this.hint,
    required this.bumped,
    required this.xray,
    required this.ink,
  });
  final ArrowsGame game;
  final double cell;
  final List<_Flight> flights;
  final Duration now;
  final int? hint;
  final int? bumped;
  final bool xray;
  final Color ink;

  Offset _pt(double x, double y) => Offset((x + 1) * cell, (y + 1) * cell);

  @override
  void paint(Canvas canvas, Size size) {
    final level = game.level;
    final dot = Paint()..color = ink.withValues(alpha: 0.18);
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        canvas.drawCircle(_pt(x.toDouble(), y.toDouble()), cell * 0.05, dot);
      }
    }
    final flying = {for (final f in flights) f.arrow: f};
    for (var i = 0; i < level.arrows.length; i++) {
      final f = flying[i];
      if (game.removed[i] && f == null) continue;
      final a = level.arrows[i];
      var color = ink;
      if (i == hint) color = Colors.amber.shade700;
      if (xray && !game.removed[i] && game.isFree(i)) {
        color = Color.lerp(ink, Colors.green, 0.45)!;
      }
      if (i == bumped && f != null && f.blocked) color = Colors.red;
      final shift = f == null
          ? 0.0
          : f.offset((now - f.start).inMicroseconds / 1e6);
      _drawArrow(canvas, a, shift, color, size);
    }
  }

  /// Draws [a] moved [shift] cells along its path (and on straight out).
  void _drawArrow(Canvas canvas, Arrow a, double shift, Color color, Size s) {
    final (dx, dy) = arrowDirs[a.dir];
    // Path points: body cells, then the way out far beyond the board.
    final pts = [
      for (final (x, y) in a.cells) (x.toDouble(), y.toDouble()),
      for (var k = 1; k <= game.level.width + game.level.height + 4; k++)
        (a.head.$1 + dx * k.toDouble(), a.head.$2 + dy * k.toDouble()),
    ];
    (double, double) at(double t) {
      final i = t.floor().clamp(0, pts.length - 2);
      final f = t - i;
      final (x1, y1) = pts[i];
      final (x2, y2) = pts[i + 1];
      return (x1 + (x2 - x1) * f, y1 + (y2 - y1) * f);
    }

    final from = shift, to = shift + a.cells.length - 1;
    final path = Path();
    var (sx, sy) = at(from);
    path.moveTo(_pt(sx, sy).dx, _pt(sx, sy).dy);
    for (var k = from.floor() + 1; k < to; k++) {
      final (x, y) = pts[k];
      path.lineTo(_pt(x, y).dx, _pt(x, y).dy);
    }
    final (hx, hy) = at(to);
    final head = _pt(hx, hy);
    path.lineTo(head.dx, head.dy);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2, cell * 0.09)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke);
    // Arrowhead.
    final dir = Offset(dx.toDouble(), dy.toDouble());
    final side = Offset(-dir.dy, dir.dx);
    final tip = head + dir * cell * 0.22;
    final tri = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (head - dir * cell * 0.12 + side * cell * 0.17).dx,
        (head - dir * cell * 0.12 + side * cell * 0.17).dy,
      )
      ..lineTo(
        (head - dir * cell * 0.12 - side * cell * 0.17).dx,
        (head - dir * cell * 0.12 - side * cell * 0.17).dy,
      )
      ..close();
    canvas.drawPath(tri, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowsPainter old) => true;
}
