import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../core/mirror.dart';
import '../../core/sound.dart';
import '../../ui/leaderboard_screen.dart';
import 'sudoku_logic.dart';

/// Endless sudoku: per level the puzzles are numbered, after one comes the
/// next. Unfinished ones are kept per level; solved ones go to the
/// leaderboard (best time per level, with a record to check, and the
/// number solved).
class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key});

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen>
    with GameMirror, WidgetsBindingObserver {
  @override
  String? get mirrorGame => 'sudoku';

  SudokuLevel level = SudokuLevel.easy;

  /// Number of the puzzle on this level (1, 2, …).
  int number = 1;
  SudokuGame? game;
  int seconds = 0;
  int? selected;
  bool notesMode = false;
  bool _solved = false;
  Timer? _clock;
  bool _paused = false;

  static String _numberKey(SudokuLevel l) => 'sudoku.n.${l.name}';
  static String _gameKey(SudokuLevel l) => 'sudoku.game.${l.name}';
  static const _levelKey = 'sudoku.level';
  static const _solvedKey = 'sudoku.solvedCount';

  @override
  void initState() {
    super.initState();
    if (mirroring) return;
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _solved || game == null || !mounted) return;
      setState(() => seconds++);
      if (seconds % 10 == 0) _save();
    });
    _start();
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (!mirroring) {
      WidgetsBinding.instance.removeObserver(this);
      _save();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (_paused) _save();
  }

  // ------------------------------------------------------------- state

  Future<void> _start({SudokuLevel? to}) async {
    final prefs = await SharedPreferences.getInstance();
    final l =
        to ??
        SudokuLevel.values.asNameMap()[prefs.getString(_levelKey)] ??
        SudokuLevel.easy;
    await prefs.setString(_levelKey, l.name);
    final n = prefs.getInt(_numberKey(l)) ?? 1;
    SudokuGame? g;
    var t = 0;
    // An unfinished one of this level goes on.
    final saved = prefs.getString(_gameKey(l));
    if (saved != null) {
      try {
        final j = jsonDecode(saved) as Map<String, dynamic>;
        if (j['n'] == n) {
          g = _restore(j, l);
          t = j['t'] as int;
        }
      } catch (_) {}
    }
    g ??= SudokuGame(
      SudokuPuzzle.generate(sudokuSeed(Leaderboard.proofOwner, l, n), l),
    );
    if (!mounted) return;
    setState(() {
      level = l;
      number = n;
      game = g;
      seconds = t;
      selected = null;
      _solved = g!.solved;
    });
  }

  static SudokuGame? _restore(Map<String, dynamic> j, SudokuLevel l) {
    final g = SudokuProof.replay({'s': j['s'], 'l': l.name, 'm': j['m']});
    final notes = j['notes'];
    if (g != null && notes is List && notes.length == 81) {
      for (var i = 0; i < 81; i++) {
        g.notes[i] = notes[i] as int;
      }
    }
    return g;
  }

  Map<String, dynamic> _state() {
    final g = game!;
    return {
      'n': number,
      's': g.puzzle.seed,
      'l': level.name,
      'm': g.log,
      'notes': g.notes,
      't': seconds,
    };
  }

  Future<void> _save() async {
    final g = game;
    if (g == null || mirroring) return;
    final prefs = await SharedPreferences.getInstance();
    if (_solved) {
      await prefs.remove(_gameKey(level));
    } else {
      await prefs.setString(_gameKey(level), jsonEncode(_state()));
    }
  }

  // ------------------------------------------------------------ mirror

  @override
  Map<String, dynamic>? mirrorState() =>
      game == null ? null : {..._state(), 'sel': selected};

  @override
  void applyMirror(Map<String, dynamic> state) {
    final l = SudokuLevel.values.asNameMap()[state['l']];
    if (l == null) return;
    final g = _restore(state, l);
    if (g == null) return;
    level = l;
    number = state['n'] as int;
    seconds = state['t'] as int;
    selected = state['sel'] as int?;
    game = g;
    _solved = g.solved;
  }

  // ------------------------------------------------------------- input

  void _enter(int value) {
    final g = game, i = selected;
    if (g == null || i == null || _solved || mirroring) return;
    final ok = notesMode && value != 0
        ? g.toggleNote(i, value)
        : g.set(i, value);
    if (!ok) return;
    Sound.play(Sfx.click, volume: 0.5);
    setState(() {});
    if (g.solved) _won();
  }

  void _undo() {
    if (_solved || mirroring) return;
    if (game?.undo() ?? false) setState(() {});
  }

  Future<void> _won() async {
    final g = game!;
    setState(() => _solved = true);
    Sound.play(Sfx.win);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gameKey(level));
    await prefs.setInt(_numberKey(level), number + 1);
    final count = (prefs.getInt(_solvedKey) ?? 0) + 1;
    await prefs.setInt(_solvedKey, count);
    final record = await Leaderboard.submit(
      'sudoku.${level.name}',
      seconds,
      proof: SudokuProof.of(g, seconds),
    );
    await Leaderboard.submit('sudoku.solved', count);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Gelöst! 🎉'),
        content: Text(
          'Sudoku ${level.label} Nr. $number in ${formatClock(seconds)}'
          '${record ? '\nNeue Bestzeit! 🏅' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.pop(context);
            },
            child: const Text('Zurück'),
          ),
          FilledButton(
            key: const ValueKey('sudokuNext'),
            onPressed: () {
              Navigator.pop(c);
              _start(to: level);
            },
            child: const Text('Nächstes Sudoku'),
          ),
        ],
      ),
    );
  }

  Future<void> _switchLevel(SudokuLevel l) async {
    if (l == level || mirroring) return;
    await _save();
    await _start(to: l);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          g == null ? 'Sudoku' : 'Sudoku Nr. $number',
          key: const ValueKey('sudokuTitle'),
        ),
        actions: [
          Center(
            child: Text(
              '⏱ ${formatClock(seconds)}',
              key: const ValueKey('sudokuClock'),
            ),
          ),
          const LeaderboardButton(game: 'sudoku'),
        ],
      ),
      body: g == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SegmentedButton<SudokuLevel>(
                          segments: [
                            for (final l in SudokuLevel.values)
                              ButtonSegment(
                                value: l,
                                label: Text(
                                  l.label,
                                  key: ValueKey('sudokuLevel-${l.name}'),
                                ),
                              ),
                          ],
                          selected: {level},
                          onSelectionChanged: mirroring
                              ? null
                              : (s) => _switchLevel(s.first),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: AspectRatio(aspectRatio: 1, child: _grid(g)),
                          ),
                        ),
                      ),
                      _tools(),
                      _pad(g),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _grid(SudokuGame g) {
    final scheme = Theme.of(context).colorScheme;
    final sel = selected;
    final selValue = sel == null ? 0 : g.cells[sel];
    final related = sel == null ? <int>{} : SudokuGame.peers(sel).toSet();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth / 9;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.onSurface, width: 2),
          ),
          child: Column(
            children: [
              for (var r = 0; r < 9; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < 9; c++)
                        Expanded(
                          child: _cell(
                            g,
                            r * 9 + c,
                            size,
                            selected: sel == r * 9 + c,
                            related: related.contains(r * 9 + c),
                            sameValue:
                                selValue != 0 && g.cells[r * 9 + c] == selValue,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(
    SudokuGame g,
    int i,
    double size, {
    required bool selected,
    required bool related,
    required bool sameValue,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final r = i ~/ 9, c = i % 9;
    final thin = BorderSide(color: scheme.outlineVariant, width: 0.5);
    final thick = BorderSide(color: scheme.onSurface, width: 1.5);
    final v = g.cells[i];
    final clash = g.clashes(i);
    final Color? bg = selected
        ? scheme.primaryContainer
        : sameValue
        ? scheme.secondaryContainer
        : related
        ? scheme.surfaceContainerHighest
        : null;
    return GestureDetector(
      key: ValueKey('sudokuCell$i'),
      behavior: HitTestBehavior.opaque,
      onTap: mirroring ? null : () => setState(() => this.selected = i),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            right: c == 8 ? BorderSide.none : (c % 3 == 2 ? thick : thin),
            bottom: r == 8 ? BorderSide.none : (r % 3 == 2 ? thick : thin),
          ),
        ),
        alignment: Alignment.center,
        child: v != 0
            ? Text(
                '$v',
                style: TextStyle(
                  fontSize: size * 0.6,
                  fontWeight: g.isGiven(i) ? FontWeight.w800 : FontWeight.w400,
                  color: clash
                      ? Colors.red
                      : g.isGiven(i)
                      ? scheme.onSurface
                      : scheme.primary,
                ),
              )
            : g.notes[i] == 0
            ? null
            : _notes(g.notes[i], size),
      ),
    );
  }

  Widget _notes(int bits, double size) {
    final style = TextStyle(
      fontSize: size * 0.24,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1,
    );
    return Padding(
      padding: EdgeInsets.all(size * 0.04),
      child: Column(
        children: [
          for (var r = 0; r < 3; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 1; c <= 3; c++)
                    Expanded(
                      child: Center(
                        child: Text(
                          bits & (1 << (r * 3 + c)) != 0 ? '${r * 3 + c}' : '',
                          style: style,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tools() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        TextButton.icon(
          key: const ValueKey('sudokuUndo'),
          onPressed: mirroring ? null : _undo,
          icon: const Icon(Icons.undo),
          label: const Text('Zurück'),
        ),
        TextButton.icon(
          key: const ValueKey('sudokuErase'),
          onPressed: mirroring ? null : () => _enter(0),
          icon: const Icon(Icons.backspace_outlined),
          label: const Text('Löschen'),
        ),
        FilterChip(
          key: const ValueKey('sudokuNotes'),
          avatar: const Icon(Icons.edit, size: 18),
          label: const Text('Notizen'),
          selected: notesMode,
          onSelected: mirroring ? null : (v) => setState(() => notesMode = v),
        ),
      ],
    ),
  );

  Widget _pad(SudokuGame g) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        for (var v = 1; v <= 9; v++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FilledButton.tonal(
                key: ValueKey('sudokuDigit$v'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 52),
                ),
                onPressed: mirroring || g.missing(v) == 0 && !notesMode
                    ? null
                    : () => _enter(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$v', style: const TextStyle(fontSize: 22)),
                    Text(
                      '${g.missing(v)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
