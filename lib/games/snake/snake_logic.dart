import 'dart:math';

enum Dir { up, down, left, right }

extension DirVector on Dir {
  (int, int) get delta => switch (this) {
    Dir.up => (0, -1),
    Dir.down => (0, 1),
    Dir.left => (-1, 0),
    Dir.right => (1, 0),
  };

  bool isOpposite(Dir other) {
    final (a, b) = delta;
    final (c, d) = other.delta;
    return a == -c && b == -d;
  }
}

/// Classic snake on a grid. Walls are deadly (optionally wrap around).
class SnakeGame {
  SnakeGame({
    this.width = 20,
    this.height = 28,
    this.wrap = false,
    Random? random,
  }) : _random = random ?? Random() {
    final cx = width ~/ 2, cy = height ~/ 2;
    body.addAll([(cx, cy), (cx, cy + 1), (cx, cy + 2)]);
    _placeFood();
  }

  final int width;
  final int height;
  final bool wrap;
  final Random _random;

  /// body.first is the head.
  final List<(int, int)> body = [];
  Dir direction = Dir.up;
  Dir? _queued;
  (int, int) food = (0, 0);
  int score = 0;
  bool dead = false;
  bool get won => body.length == width * height;

  /// Speed in steps per second; grows with the score.
  double get speed => min(16, 6 + score * 0.25);

  /// Queues a direction change (ignored if it would reverse the snake).
  void turn(Dir d) {
    final base = _queued ?? direction;
    if (d == base || d.isOpposite(direction)) return;
    _queued = d;
  }

  void _placeFood() {
    final free = <(int, int)>[
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          if (!body.contains((x, y))) (x, y),
    ];
    if (free.isNotEmpty) food = free[_random.nextInt(free.length)];
  }

  /// Advances one step.
  void step() {
    if (dead || won) return;
    if (_queued != null) {
      direction = _queued!;
      _queued = null;
    }
    final (dx, dy) = direction.delta;
    var (x, y) = body.first;
    x += dx;
    y += dy;
    if (wrap) {
      x = (x + width) % width;
      y = (y + height) % height;
    } else if (x < 0 || y < 0 || x >= width || y >= height) {
      dead = true;
      return;
    }
    final eats = (x, y) == food;
    // The tail moves away this step unless the snake grows.
    final checkBody = eats ? body : body.sublist(0, body.length - 1);
    if (checkBody.contains((x, y))) {
      dead = true;
      return;
    }
    body.insert(0, (x, y));
    if (eats) {
      score++;
      _placeFood();
    } else {
      body.removeLast();
    }
  }
}
