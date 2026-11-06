import '../../core/proof.dart';

enum SudokuLevel {
  easy('Leicht', 38),
  medium('Mittel', 31),
  hard('Schwer', 25);

  const SudokuLevel(this.label, this.givens);
  final String label;

  /// Numbers shown at the start (fewer when the puzzle allows no more
  /// removals with a unique solution).
  final int givens;
}

/// Solves [cells] (81 values, 0 = empty) and counts solutions up to
/// [limit]. With [solution] the first one found is written there.
int countSolutions(List<int> cells, {int limit = 2, List<int>? solution}) {
  final grid = List<int>.from(cells);
  final rows = List.filled(9, 0), cols = List.filled(9, 0);
  final boxes = List.filled(9, 0);
  for (var i = 0; i < 81; i++) {
    final v = grid[i];
    if (v == 0) continue;
    final bit = 1 << v;
    final r = i ~/ 9, c = i % 9, b = (r ~/ 3) * 3 + c ~/ 3;
    // A clash in the start: no solution.
    if ((rows[r] | cols[c] | boxes[b]) & bit != 0) return 0;
    rows[r] |= bit;
    cols[c] |= bit;
    boxes[b] |= bit;
  }
  var found = 0;
  bool search() {
    // The empty cell with the fewest options first.
    var best = -1, bestCount = 10, bestFree = 0;
    for (var i = 0; i < 81; i++) {
      if (grid[i] != 0) continue;
      final r = i ~/ 9, c = i % 9, b = (r ~/ 3) * 3 + c ~/ 3;
      final free = ~(rows[r] | cols[c] | boxes[b]) & 0x3fe;
      var n = 0;
      for (var x = free; x != 0; x &= x - 1) {
        n++;
      }
      if (n < bestCount) {
        best = i;
        bestCount = n;
        bestFree = free;
        if (n <= 1) break;
      }
    }
    if (best < 0) {
      found++;
      if (found == 1 && solution != null) {
        solution.setAll(0, grid);
      }
      return found >= limit;
    }
    final r = best ~/ 9, c = best % 9, b = (r ~/ 3) * 3 + c ~/ 3;
    for (var v = 1; v <= 9; v++) {
      final bit = 1 << v;
      if (bestFree & bit == 0) continue;
      grid[best] = v;
      rows[r] |= bit;
      cols[c] |= bit;
      boxes[b] |= bit;
      if (search()) return true;
      rows[r] &= ~bit;
      cols[c] &= ~bit;
      boxes[b] &= ~bit;
    }
    grid[best] = 0;
    return false;
  }

  search();
  return found;
}

/// A sudoku with exactly one solution, made from [seed]: the same seed
/// gives the same puzzle on every device ([SeededRandom]).
class SudokuPuzzle {
  SudokuPuzzle._(this.seed, this.level, this.givens, this.solution);

  factory SudokuPuzzle.generate(String seed, SudokuLevel level) {
    final r = SeededRandom('sudoku:${level.name}:$seed');
    // A full grid: backtracking with the digits in random order.
    final full = List.filled(81, 0);
    bool fill(int i) {
      if (i == 81) return true;
      final r0 = i ~/ 9, c0 = i % 9;
      final digits = [for (var v = 1; v <= 9; v++) v]..shuffle(r);
      for (final v in digits) {
        if (!_fits(full, r0, c0, v)) continue;
        full[i] = v;
        if (fill(i + 1)) return true;
      }
      full[i] = 0;
      return false;
    }

    fill(0);
    // Take numbers away as long as the solution stays unique.
    final puzzle = List<int>.from(full);
    final order = [for (var i = 0; i < 81; i++) i]..shuffle(r);
    var shown = 81;
    for (final i in order) {
      if (shown <= level.givens) break;
      final keep = puzzle[i];
      puzzle[i] = 0;
      if (countSolutions(puzzle) == 1) {
        shown--;
      } else {
        puzzle[i] = keep;
      }
    }
    return SudokuPuzzle._(seed, level, puzzle, full);
  }

  final String seed;
  final SudokuLevel level;

  /// 81 values row by row, 0 = to fill in.
  final List<int> givens;
  final List<int> solution;

  static bool _fits(List<int> g, int r, int c, int v) {
    for (var k = 0; k < 9; k++) {
      if (g[r * 9 + k] == v || g[k * 9 + c] == v) return false;
    }
    final br = r - r % 3, bc = c - c % 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        if (g[(br + dr) * 9 + bc + dc] == v) return false;
      }
    }
    return true;
  }
}

/// A sudoku being solved. Every entry is recorded (`'<cell>.<value>'`,
/// value 0 = cleared) for the leaderboard check (see [SudokuProof]).
class SudokuGame {
  SudokuGame(this.puzzle) : cells = List.of(puzzle.givens);

  final SudokuPuzzle puzzle;
  final List<int> cells;

  /// Pencil marks per cell (bits 1–9).
  final List<int> notes = List.filled(81, 0);
  final List<String> log = [];

  /// For undo: (cell, value before, notes before).
  final List<(int, int, int)> _history = [];

  bool isGiven(int i) => puzzle.givens[i] != 0;

  bool get solved {
    for (var i = 0; i < 81; i++) {
      if (cells[i] != puzzle.solution[i]) return false;
    }
    return true;
  }

  /// Sets [value] (1–9) in cell [i], or clears it with 0.
  bool set(int i, int value) {
    if (i < 0 || i > 80 || value < 0 || value > 9 || isGiven(i)) return false;
    if (cells[i] == value && value != 0) return false;
    if (value == 0 && cells[i] == 0 && notes[i] == 0) return false;
    _history.add((i, cells[i], notes[i]));
    cells[i] = value;
    if (value != 0) {
      notes[i] = 0;
      // The number is no longer possible in the same row, column and box.
      for (final j in peers(i)) {
        notes[j] &= ~(1 << value);
      }
    } else {
      notes[i] = 0;
    }
    log.add('$i.$value');
    return true;
  }

  /// Switches pencil mark [value] in an empty cell.
  bool toggleNote(int i, int value) {
    if (i < 0 || i > 80 || value < 1 || value > 9) return false;
    if (isGiven(i) || cells[i] != 0) return false;
    notes[i] ^= 1 << value;
    return true;
  }

  bool undo() {
    if (_history.isEmpty) return false;
    final (i, value, before) = _history.removeLast();
    cells[i] = value;
    notes[i] = before;
    log.add('$i.$value');
    return true;
  }

  /// Cells in the same row, column or box as [i].
  static Iterable<int> peers(int i) sync* {
    final r = i ~/ 9, c = i % 9, br = r - r % 3, bc = c - c % 3;
    for (var j = 0; j < 81; j++) {
      if (j == i) continue;
      final rj = j ~/ 9, cj = j % 9;
      if (rj == r || cj == c || (rj - rj % 3 == br && cj - cj % 3 == bc)) {
        yield j;
      }
    }
  }

  /// Whether the number in [i] clashes with another in its row, column or
  /// box.
  bool clashes(int i) {
    final v = cells[i];
    if (v == 0) return false;
    return peers(i).any((j) => cells[j] == v);
  }

  /// How often [value] is still missing.
  int missing(int value) => 9 - cells.where((v) => v == value).length;
}

/// Record of a checked sudoku: seed (starting with the player's key, so
/// nobody can hand in somebody else's game), level, all entries and the
/// time. Others make the same puzzle, replay the entries and check the
/// result; the time cannot be proven, but needs at least
/// [secondsPerEntry] per entry.
class SudokuProof {
  SudokuProof._();

  static const secondsPerEntry = 0.4;

  static Map<String, dynamic> of(SudokuGame g, int seconds) => {
    's': g.puzzle.seed,
    'l': g.puzzle.level.name,
    'm': g.log,
    't': seconds,
  };

  /// Replays [proof]; null if malformed or an entry is impossible.
  static SudokuGame? replay(Object? proof) {
    final p = readProof(proof, maxMoves: 2000);
    if (p == null || proof is! Map) return null;
    final level = SudokuLevel.values.asNameMap()[proof['l']];
    if (level == null) return null;
    final g = SudokuGame(SudokuPuzzle.generate(p.$1, level));
    for (final m in p.$2) {
      final parts = m.split('.');
      if (parts.length != 2) return null;
      final i = int.tryParse(parts[0]), v = int.tryParse(parts[1]);
      if (i == null || v == null) return null;
      // Undo is recorded as the value it restores.
      if (i < 0 || i > 80 || v < 0 || v > 9 || g.isGiven(i)) return null;
      g.cells[i] = v;
      g.log.add(m);
    }
    return g;
  }

  /// The time of the solved sudoku on board [board] if it belongs to
  /// [author], else null.
  static int? verify(String board, Object? proof, String author) {
    if (proof is! Map || proof['s'] is! String) return null;
    if (!seedOwnedBy(proof['s'] as String, author)) return null;
    if (board != 'sudoku.${proof['l']}') return null;
    final t = proof['t'];
    final g = replay(proof);
    if (g == null || !g.solved || t is! int) return null;
    if (t < g.log.length * secondsPerEntry) return null;
    return t;
  }
}

/// "4:05", "1:02:03".
String formatClock(int seconds) {
  final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// Seed of the [n]th sudoku of [level] for player [owner].
String sudokuSeed(String owner, SudokuLevel level, int n) =>
    '$owner:sudoku-${level.name}-$n';
