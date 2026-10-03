import 'dart:math';

/// Fleet according to the common German rules: 1×5, 1×4, 2×3, 1×2.
const fleetSizes = [5, 4, 3, 3, 2];
const boardSize = 10;

class Ship {
  Ship(this.cells);
  final List<(int, int)> cells;
  final Set<(int, int)> hits = {};
  bool get sunk => hits.length == cells.length;
}

enum ShotResult { miss, hit, sunk }

class ShotOutcome {
  const ShotOutcome(
    this.result, {
    this.sunkCells = const [],
    this.fleetDestroyed = false,
  });
  final ShotResult result;
  final List<(int, int)> sunkCells;
  final bool fleetDestroyed;

  Map<String, dynamic> toJson() => {
    'result': result.name,
    'sunk': [
      for (final (x, y) in sunkCells) [x, y],
    ],
    'over': fleetDestroyed,
  };

  factory ShotOutcome.fromJson(Map<String, dynamic> j) => ShotOutcome(
    ShotResult.values.byName(j['result'] as String),
    sunkCells: [
      for (final c in (j['sunk'] as List? ?? const []))
        ((c as List)[0] as int, c[1] as int),
    ],
    fleetDestroyed: j['over'] as bool? ?? false,
  );
}

/// A player's own board with ships. Ships may not touch each other
/// (not even diagonally).
class FleetBoard {
  FleetBoard();

  /// A saved board (see [toJson]).
  factory FleetBoard.fromJson(Map<String, dynamic> j) {
    List<(int, int)> cells(Object? raw) => [
      for (final c in (raw as List).cast<List<dynamic>>())
        (c[0] as int, c[1] as int),
    ];
    final b = FleetBoard();
    for (final s in (j['ships'] as List).cast<Map<String, dynamic>>()) {
      b.ships.add(Ship(cells(s['cells']))..hits.addAll(cells(s['hits'])));
    }
    b.shotsReceived.addAll(cells(j['shots']));
    return b;
  }

  Map<String, dynamic> toJson() {
    List<List<int>> cells(Iterable<(int, int)> c) => [
      for (final (x, y) in c) [x, y],
    ];
    return {
      'ships': [
        for (final s in ships) {'cells': cells(s.cells), 'hits': cells(s.hits)},
      ],
      'shots': cells(shotsReceived),
    };
  }

  final List<Ship> ships = [];
  final Set<(int, int)> shotsReceived = {};

  Ship? shipAt(int x, int y) {
    for (final s in ships) {
      if (s.cells.contains((x, y))) return s;
    }
    return null;
  }

  static List<(int, int)> cellsFor(int x, int y, int length, bool horizontal) =>
      [for (var i = 0; i < length; i++) horizontal ? (x + i, y) : (x, y + i)];

  bool canPlace(List<(int, int)> cells, {Ship? ignore}) {
    for (final (x, y) in cells) {
      if (x < 0 || y < 0 || x >= boardSize || y >= boardSize) return false;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final other = shipAt(x + dx, y + dy);
          if (other != null && other != ignore) return false;
        }
      }
    }
    return true;
  }

  bool place(int x, int y, int length, bool horizontal) {
    final cells = cellsFor(x, y, length, horizontal);
    if (!canPlace(cells)) return false;
    ships.add(Ship(cells));
    return true;
  }

  /// Places the whole fleet randomly.
  static FleetBoard random([Random? random]) {
    final r = random ?? Random();
    while (true) {
      final b = FleetBoard();
      var ok = true;
      for (final len in fleetSizes) {
        var placed = false;
        for (var attempt = 0; attempt < 200 && !placed; attempt++) {
          placed = b.place(
            r.nextInt(boardSize),
            r.nextInt(boardSize),
            len,
            r.nextBool(),
          );
        }
        if (!placed) {
          ok = false;
          break;
        }
      }
      if (ok) return b;
    }
  }

  bool get allSunk => ships.isNotEmpty && ships.every((s) => s.sunk);

  ShotOutcome receiveShot(int x, int y) {
    shotsReceived.add((x, y));
    final ship = shipAt(x, y);
    if (ship == null) return const ShotOutcome(ShotResult.miss);
    ship.hits.add((x, y));
    if (ship.sunk) {
      return ShotOutcome(
        ShotResult.sunk,
        sunkCells: ship.cells,
        fleetDestroyed: allSunk,
      );
    }
    return const ShotOutcome(ShotResult.hit);
  }
}

enum TargetCell { unknown, miss, hit, sunk }

/// What a player knows about the opponent's board.
class TargetBoard {
  final List<List<TargetCell>> cells = List.generate(
    boardSize,
    (_) => List.filled(boardSize, TargetCell.unknown),
  );

  bool canShoot(int x, int y) => cells[y][x] == TargetCell.unknown;

  List<List<int>> toJson() => [
    for (final row in cells) [for (final c in row) c.index],
  ];

  /// Loads a saved board (see [toJson]).
  void load(List<dynamic> j) {
    for (var y = 0; y < boardSize; y++) {
      final row = (j[y] as List).cast<int>();
      for (var x = 0; x < boardSize; x++) {
        cells[y][x] = TargetCell.values[row[x]];
      }
    }
  }

  void apply(int x, int y, ShotOutcome o) {
    switch (o.result) {
      case ShotResult.miss:
        cells[y][x] = TargetCell.miss;
      case ShotResult.hit:
        cells[y][x] = TargetCell.hit;
      case ShotResult.sunk:
        for (final (sx, sy) in o.sunkCells) {
          cells[sy][sx] = TargetCell.sunk;
        }
        // Cells around a sunk ship cannot contain ships.
        for (final (sx, sy) in o.sunkCells) {
          for (var dx = -1; dx <= 1; dx++) {
            for (var dy = -1; dy <= 1; dy++) {
              final nx = sx + dx, ny = sy + dy;
              if (nx >= 0 &&
                  ny >= 0 &&
                  nx < boardSize &&
                  ny < boardSize &&
                  cells[ny][nx] == TargetCell.unknown) {
                cells[ny][nx] = TargetCell.miss;
              }
            }
          }
        }
    }
  }
}

/// Computer opponent: random "hunt" mode, then "target" mode around hits.
class BattleshipAi {
  BattleshipAi([Random? random]) : _random = random ?? Random();
  final Random _random;
  final TargetBoard knowledge = TargetBoard();

  (int, int) nextShot() {
    final hits = <(int, int)>[];
    for (var y = 0; y < boardSize; y++) {
      for (var x = 0; x < boardSize; x++) {
        if (knowledge.cells[y][x] == TargetCell.hit) hits.add((x, y));
      }
    }
    if (hits.isNotEmpty) {
      final candidates = <(int, int)>[];
      final horizontal =
          hits.length > 1 && hits.every((h) => h.$2 == hits.first.$2);
      final vertical =
          hits.length > 1 && hits.every((h) => h.$1 == hits.first.$1);
      for (final (x, y) in hits) {
        final dirs = horizontal
            ? const [(1, 0), (-1, 0)]
            : vertical
            ? const [(0, 1), (0, -1)]
            : const [(1, 0), (-1, 0), (0, 1), (0, -1)];
        for (final (dx, dy) in dirs) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 &&
              ny >= 0 &&
              nx < boardSize &&
              ny < boardSize &&
              knowledge.canShoot(nx, ny)) {
            candidates.add((nx, ny));
          }
        }
      }
      if (candidates.isNotEmpty) {
        return candidates[_random.nextInt(candidates.length)];
      }
    }
    // Hunt on a checkerboard pattern: every ship covers at least one such cell.
    final open = <(int, int)>[];
    final parity = <(int, int)>[];
    for (var y = 0; y < boardSize; y++) {
      for (var x = 0; x < boardSize; x++) {
        if (!knowledge.canShoot(x, y)) continue;
        open.add((x, y));
        if ((x + y).isEven) parity.add((x, y));
      }
    }
    final pool = parity.isNotEmpty ? parity : open;
    return pool[_random.nextInt(pool.length)];
  }

  void learn(int x, int y, ShotOutcome o) => knowledge.apply(x, y, o);
}
