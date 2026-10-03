import 'dart:math';

/// A tile slot in the layout. Coordinates are in half-tile units so tiles
/// can overlap by half a tile; z is the layer.
class Slot {
  const Slot(this.x, this.y, this.z);
  final int x;
  final int y;
  final int z;
}

/// Symbol of a tile. Two tiles match when their faces are equal.
class TileFace {
  const TileFace(this.suit, this.rank);
  final String suit; // 'man', 'pin', 'sou', 'wind', 'dragon'
  final int rank;

  @override
  bool operator ==(Object other) =>
      other is TileFace && other.suit == suit && other.rank == rank;
  @override
  int get hashCode => Object.hash(suit, rank);

  String get symbol {
    switch (suit) {
      case 'wind':
        return const ['東', '南', '西', '北'][rank];
      case 'dragon':
        return const ['中', '發', '白'][rank];
      default:
        return '${rank + 1}';
    }
  }

  String get subtitle => switch (suit) {
    'man' => '萬',
    'pin' => '●',
    'sou' => '竹',
    _ => '',
  };
}

final List<TileFace> allFaces = [
  for (final s in ['man', 'pin', 'sou'])
    for (var r = 0; r < 9; r++) TileFace(s, r),
  for (var r = 0; r < 4; r++) TileFace('wind', r),
  for (var r = 0; r < 3; r++) TileFace('dragon', r),
];

/// Tall pyramid for portrait screens: 108 tiles in 4 layers.
List<Slot> towerLayout() => [
  for (var y = 0; y < 10; y++)
    for (var x = 0; x < 6; x++) Slot(x * 2, y * 2, 0),
  for (var y = 0; y < 8; y++)
    for (var x = 0; x < 4; x++) Slot(2 + x * 2, 2 + y * 2, 1),
  for (var y = 0; y < 6; y++)
    for (var x = 0; x < 2; x++) Slot(4 + x * 2, 4 + y * 2, 2),
  for (var y = 0; y < 2; y++)
    for (var x = 0; x < 2; x++) Slot(4 + x * 2, 8 + y * 2, 3),
];

/// Wide pyramid for landscape screens: 120 tiles in 4 layers.
List<Slot> pyramidLayout() => [
  for (var y = 0; y < 6; y++)
    for (var x = 0; x < 12; x++) Slot(x * 2, y * 2, 0),
  for (var y = 0; y < 4; y++)
    for (var x = 0; x < 8; x++) Slot(4 + x * 2, 2 + y * 2, 1),
  for (var y = 0; y < 2; y++)
    for (var x = 0; x < 6; x++) Slot(6 + x * 2, 4 + y * 2, 2),
  for (var y = 0; y < 2; y++)
    for (var x = 0; x < 2; x++) Slot(10 + x * 2, 4 + y * 2, 3),
];

class MahjongTile {
  MahjongTile(this.id, this.slot, this.face);
  final int id;
  final Slot slot;
  TileFace face;
  bool removed = false;
}

class MahjongGame {
  MahjongGame(this.tiles);

  /// Creates a game that is guaranteed to be solvable: tiles are removed
  /// pairwise from the full layout in a random legal order and each removed
  /// pair gets the same face. Replaying that order solves the game.
  factory MahjongGame.generate({List<Slot>? layout, Random? random}) {
    final r = random ?? Random();
    final slots = layout ?? pyramidLayout();
    assert(slots.length.isEven);
    while (true) {
      final game = MahjongGame([
        for (var i = 0; i < slots.length; i++)
          MahjongTile(i, slots[i], allFaces.first),
      ]);
      final faces = <TileFace>[];
      // Each face is used in pairs of pairs (4 tiles) as in the real game.
      final pairCount = slots.length ~/ 2;
      for (var i = 0; i < pairCount; i++) {
        faces.add(allFaces[(i ~/ 2) % allFaces.length]);
      }
      faces.shuffle(r);
      var ok = true;
      final solution = <(int, int)>[];
      for (final face in faces) {
        final free = game.tiles
            .where((t) => !t.removed && game.isFree(t))
            .toList();
        if (free.length < 2) {
          ok = false;
          break;
        }
        free.shuffle(r);
        free[0]
          ..face = face
          ..removed = true;
        free[1]
          ..face = face
          ..removed = true;
        solution.add((free[0].id, free[1].id));
      }
      if (!ok) continue;
      for (final t in game.tiles) {
        t.removed = false;
      }
      game.solution = solution;
      return game;
    }
  }

  /// A saved game on [layout] (see [toJson]).
  factory MahjongGame.fromJson(List<Slot> layout, Map<String, dynamic> j) {
    final faces = (j['faces'] as List).cast<int>();
    final removed = (j['removed'] as List).cast<int>().toSet();
    if (faces.length != layout.length) {
      throw const FormatException('layout changed');
    }
    final game = MahjongGame([
      for (var i = 0; i < layout.length; i++)
        MahjongTile(i, layout[i], allFaces[faces[i]])
          ..removed = removed.contains(i),
    ]);
    for (final p in (j['history'] as List).cast<List<dynamic>>()) {
      game.history.add((game.tiles[p[0] as int], game.tiles[p[1] as int]));
    }
    return game;
  }

  Map<String, dynamic> toJson() => {
    'faces': [for (final t in tiles) allFaces.indexOf(t.face)],
    'removed': [
      for (final t in tiles)
        if (t.removed) t.id,
    ],
    'history': [
      for (final (a, b) in history) [a.id, b.id],
    ],
  };

  final List<MahjongTile> tiles;
  final List<(MahjongTile, MahjongTile)> history = [];

  /// Pairs of tile ids in an order that solves the generated board.
  List<(int, int)> solution = const [];

  int get remaining => tiles.where((t) => !t.removed).length;
  bool get won => remaining == 0;

  bool _overlapsXY(Slot a, Slot b) =>
      (a.x - b.x).abs() < 2 && (a.y - b.y).abs() < 2;

  /// A tile is free if nothing lies on top of it and its left or right
  /// side is open.
  bool isFree(MahjongTile t) {
    if (t.removed) return false;
    var leftBlocked = false, rightBlocked = false;
    for (final o in tiles) {
      if (o.removed || o == t) continue;
      final a = t.slot, b = o.slot;
      if (b.z > a.z && _overlapsXY(a, b)) return false;
      if (b.z == a.z && (a.y - b.y).abs() < 2) {
        if (b.x == a.x - 2) leftBlocked = true;
        if (b.x == a.x + 2) rightBlocked = true;
      }
    }
    return !(leftBlocked && rightBlocked);
  }

  bool canMatch(MahjongTile a, MahjongTile b) =>
      a != b && a.face == b.face && isFree(a) && isFree(b);

  bool match(MahjongTile a, MahjongTile b) {
    if (!canMatch(a, b)) return false;
    a.removed = true;
    b.removed = true;
    history.add((a, b));
    return true;
  }

  bool undo() {
    if (history.isEmpty) return false;
    final (a, b) = history.removeLast();
    a.removed = false;
    b.removed = false;
    return true;
  }

  /// A currently possible pair, or null if there is none.
  (MahjongTile, MahjongTile)? hint() {
    final free = tiles.where(isFree).toList();
    for (var i = 0; i < free.length; i++) {
      for (var j = i + 1; j < free.length; j++) {
        if (free[i].face == free[j].face) return (free[i], free[j]);
      }
    }
    return null;
  }

  bool get stuck => !won && hint() == null;

  /// Shuffles the faces of the remaining tiles (when stuck).
  void shuffleRemaining([Random? random]) {
    final r = random ?? Random();
    final left = tiles.where((t) => !t.removed).toList();
    for (var attempt = 0; attempt < 50; attempt++) {
      final faces = left.map((t) => t.face).toList()..shuffle(r);
      for (var i = 0; i < left.length; i++) {
        left[i].face = faces[i];
      }
      if (hint() != null) return;
    }
  }
}
