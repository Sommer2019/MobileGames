import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/mirror.dart';
import '../../core/saved_games.dart';
import '../../core/sound.dart';
import '../../ui/leaderboard_screen.dart';
import 'mahjong_logic.dart';

class MahjongScreen extends StatefulWidget {
  const MahjongScreen({super.key});

  @override
  State<MahjongScreen> createState() => _MahjongScreenState();
}

class _MahjongScreenState extends State<MahjongScreen>
    with SavedGameState, GameMirror, SavedGameMirror {
  @override
  String? get mirrorGame => 'mahjong';

  MahjongGame? game;
  MahjongTile? selected;
  (MahjongTile, MahjongTile)? hint;
  MahjongShape? _shape;
  static const _shapeKey = 'mahjong.shape';
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;

  /// Playing time before the round was saved.
  int _offset = 0;
  int get _seconds => _offset + _clock.elapsed.inSeconds;

  @override
  String get saveKey => 'mahjong';

  @override
  Map<String, dynamic>? saveGame() {
    final g = game;
    if (g == null || (!savingForMirror && (g.won || g.history.isEmpty))) {
      return null;
    }
    return {'shape': _shape!.name, 'game': g.toJson(), 'seconds': _seconds};
  }

  @override
  void restoreGame(Map<String, dynamic> data) {
    // Older saves only knew portrait (pyramid) or landscape (wide).
    final shape =
        MahjongShape.values.asNameMap()[data['shape']] ??
        (data['portrait'] == false ? MahjongShape.wide : MahjongShape.pyramid);
    game = MahjongGame.fromJson(
      shape.layout(),
      data['game'] as Map<String, dynamic>,
    );
    _shape = shape;
    _offset = data['seconds'] as int;
    _clock
      ..reset()
      ..start();
  }

  /// The shape chosen last time (null: by screen orientation).
  MahjongShape? _savedShape;

  Future<void> _loadShape() async {
    final prefs = await SharedPreferences.getInstance();
    _savedShape = MahjongShape.values.asNameMap()[prefs.getString(_shapeKey)];
    // A fresh game (nothing played yet) switches to the remembered shape.
    final saved = _savedShape;
    if (!mounted || saved == null || saved == _shape) return;
    if (game != null && game!.history.isEmpty && !restoredGame) {
      setState(() => _newGame(saved));
    }
  }

  Future<void> _chooseShape(MahjongShape s) async {
    setState(() => _newGame(s));
    _savedShape = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shapeKey, s.name);
  }

  @override
  void initState() {
    super.initState();
    _loadShape();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newGame(MahjongShape shape) {
    _shape = shape;
    game = MahjongGame.generate(layout: shape.layout());
    selected = null;
    hint = null;
    _offset = 0;
    _clock
      ..reset()
      ..start();
  }

  void _tap(MahjongTile t) {
    final g = game!;
    if (!g.isFree(t)) return;
    setState(() {
      hint = null;
      final s = selected;
      if (s == null || s == t) {
        selected = s == t ? null : t;
        return;
      }
      if (g.match(s, t)) {
        selected = null;
        Sound.play(g.won ? Sfx.win : Sfx.click);
        if (g.won) {
          _clock.stop();
          Leaderboard.submit(_shape!.board, _seconds);
          _showWin();
        } else if (g.stuck) {
          _showStuck();
        }
      } else {
        selected = t;
      }
    });
  }

  void _showWin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Gewonnen! 🎉'),
          content: Text('Alle Steine abgeräumt in ${_formatTime()}.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() => _newGame(_shape!));
              },
              child: const Text('Neues Spiel'),
            ),
          ],
        ),
      );
    });
  }

  void _showStuck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keine Züge mehr'),
          content: const Text(
            'Es gibt kein freies Paar mehr. Mischen oder Zug zurücknehmen?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() => game!.undo());
              },
              child: const Text('Rückgängig'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                setState(() => game!.shuffleRemaining());
              },
              child: const Text('Mischen'),
            ),
          ],
        ),
      );
    });
  }

  String _formatTime() {
    final s = _seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mahjong'),
        actions: [
          PopupMenuButton<MahjongShape>(
            key: const ValueKey('mahjongShape'),
            tooltip: 'Form',
            icon: const Icon(Icons.view_quilt),
            onSelected: _chooseShape,
            itemBuilder: (_) => [
              for (final s in MahjongShape.values)
                CheckedPopupMenuItem(
                  key: ValueKey('shape-${s.name}'),
                  value: s,
                  checked: s == _shape,
                  child: Text(s.label),
                ),
            ],
          ),
          LeaderboardButton(game: 'mahjong', board: _shape?.board),
          IconButton(
            tooltip: 'Rückgängig',
            icon: const Icon(Icons.undo),
            onPressed: () => setState(() {
              game?.undo();
              selected = null;
            }),
          ),
          IconButton(
            tooltip: 'Tipp',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => setState(() => hint = game?.hint()),
          ),
          IconButton(
            tooltip: 'Neues Spiel',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _newGame(_shape!)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            if (game == null) {
              _newGame(
                _savedShape ??
                    (c.maxHeight >= c.maxWidth
                        ? MahjongShape.pyramid
                        : MahjongShape.wide),
              );
            }
            final g = game!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${_shape!.label}   •   Steine: ${g.remaining}   •   '
                    'Zeit: ${_formatTime()}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(child: _board(g)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _board(MahjongGame g) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxX = g.tiles.map((t) => t.slot.x).reduce(max) + 2;
        final maxY = g.tiles.map((t) => t.slot.y).reduce(max) + 2;
        final maxZ = g.tiles.map((t) => t.slot.z).reduce(max);
        // Tile aspect 3:4; each slot unit is half a tile.
        const depthFactor = 0.12;
        final unitW = min(
          (c.maxWidth - 16) / (maxX / 2 + maxZ * depthFactor) / 2,
          (c.maxHeight - 16) /
              (maxY / 2 * 4 / 3 + maxZ * depthFactor) /
              2 *
              3 /
              4,
        );
        final tileW = unitW * 2, tileH = tileW * 4 / 3;
        final depth = tileW * depthFactor;
        final boardW = maxX / 2 * tileW + maxZ * depth;
        final boardH = maxY / 2 * tileH + maxZ * depth;
        final visible = g.tiles.where((t) => !t.removed).toList()
          ..sort((a, b) {
            if (a.slot.z != b.slot.z) return a.slot.z - b.slot.z;
            if (a.slot.y != b.slot.y) return a.slot.y - b.slot.y;
            return a.slot.x - b.slot.x;
          });
        return Center(
          child: SizedBox(
            width: boardW,
            height: boardH,
            child: Stack(
              children: [
                for (final t in visible)
                  Positioned(
                    left: t.slot.x / 2 * tileW + (maxZ - t.slot.z) * depth,
                    top: t.slot.y / 2 * tileH + (maxZ - t.slot.z) * depth,
                    width: tileW + depth,
                    height: tileH + depth,
                    child: _tile(g, t, tileW, tileH, depth),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(MahjongGame g, MahjongTile t, double w, double h, double depth) {
    final free = g.isFree(t);
    final isSel = selected == t;
    final isHint = hint != null && (hint!.$1 == t || hint!.$2 == t);
    final face = t.face;
    final color = switch (face.suit) {
      'man' => const Color(0xFFC62828),
      'pin' => const Color(0xFF1565C0),
      'sou' => const Color(0xFF2E7D32),
      'wind' => const Color(0xFF212121),
      _ => const [
        Color(0xFFC62828),
        Color(0xFF2E7D32),
        Color(0xFF1565C0),
      ][face.rank],
    };
    return GestureDetector(
      onTap: () => _tap(t),
      child: Stack(
        children: [
          // Side of the tile (3D effect).
          Positioned(
            left: depth,
            top: depth,
            width: w,
            height: h,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFBCAA84),
                borderRadius: BorderRadius.circular(w * 0.12),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: w,
            height: h,
            child: Container(
              decoration: BoxDecoration(
                color: isSel
                    ? const Color(0xFFFFF59D)
                    : isHint
                    ? const Color(0xFFB2EBF2)
                    : free
                    ? const Color(0xFFFFFDF5)
                    : const Color(0xFFE6E0D0),
                borderRadius: BorderRadius.circular(w * 0.12),
                border: Border.all(
                  color: isSel ? Colors.orange : const Color(0xFF9E8F6A),
                  width: isSel ? 2 : 0.8,
                ),
              ),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        face.symbol,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color,
                          height: 1.1,
                        ),
                      ),
                      if (face.subtitle.isNotEmpty)
                        Text(
                          face.subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: color,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
