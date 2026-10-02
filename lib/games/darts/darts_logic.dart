import 'dart:math';

/// Standard dartboard dimensions in millimetres.
class Board {
  static const bullInner = 6.35;
  static const bullOuter = 15.9;
  static const tripleInner = 99.0;
  static const tripleOuter = 107.0;
  static const doubleInner = 162.0;
  static const doubleOuter = 170.0;

  /// Segment numbers clockwise starting at the top.
  static const numbers = [
    20,
    1,
    18,
    4,
    13,
    6,
    10,
    15,
    2,
    17,
    3,
    19,
    7,
    16,
    8,
    11,
    14,
    9,
    12,
    5,
  ];

  /// Scores a dart at (x, y) mm relative to the centre (y pointing down).
  static DartHit score(double x, double y) {
    final r = sqrt(x * x + y * y);
    if (r > doubleOuter) return const DartHit(0, 0);
    if (r <= bullInner) return const DartHit(25, 2);
    if (r <= bullOuter) return const DartHit(25, 1);
    // Angle clockwise from the top in degrees.
    final deg = (atan2(x, -y) * 180 / pi + 360) % 360;
    final segment = numbers[((deg + 9) % 360 ~/ 18)];
    final mult = (r >= tripleInner && r <= tripleOuter)
        ? 3
        : (r >= doubleInner)
        ? 2
        : 1;
    return DartHit(segment, mult);
  }

  /// Centre of a segment's single area, for tests and the AI.
  static (double, double) aimPoint(int number, {int multiplier = 1}) {
    if (number == 25) return (0, 0);
    final i = numbers.indexOf(number);
    final angle = i * 18 * pi / 180;
    final r = switch (multiplier) {
      3 => (tripleInner + tripleOuter) / 2,
      2 => (doubleInner + doubleOuter) / 2,
      _ => (bullOuter + tripleInner) / 2,
    };
    return (sin(angle) * r, -cos(angle) * r);
  }
}

class DartHit {
  const DartHit(this.value, this.multiplier);
  final int value; // 1..20, 25 = bull, 0 = miss
  final int multiplier;

  int get points => value * multiplier;
  bool get isMiss => multiplier == 0;
  bool get isDouble => multiplier == 2;

  String get label {
    if (isMiss) return 'Daneben';
    if (value == 25) return multiplier == 2 ? 'Bull' : '25';
    return '${const ['', 'S', 'D', 'T'][multiplier]}$value';
  }
}

enum DartsMode { x501, x301, aroundTheClock }

extension DartsModeName on DartsMode {
  String get label => switch (this) {
    DartsMode.x501 => '501',
    DartsMode.x301 => '301',
    DartsMode.aroundTheClock => 'Rund um die Uhr',
  };
}

class DartsPlayerState {
  DartsPlayerState(this.remaining);
  int remaining; // X01: points left; ATC: index of next target (0..20)
  int darts = 0;
  int scoredPoints = 0;

  /// Average points per three darts (X01).
  double get average => darts == 0 ? 0 : scoredPoints / darts * 3;
}

/// Turn based darts for 1–4 players.
class DartsGame {
  DartsGame({required this.players, required this.mode, this.doubleOut = true})
    : states = List.generate(
        players,
        (_) => DartsPlayerState(switch (mode) {
          DartsMode.x501 => 501,
          DartsMode.x301 => 301,
          DartsMode.aroundTheClock => 0,
        }),
      );

  /// Targets for "Rund um die Uhr": 1..20, then the bull.
  static const clockTargets = [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    25,
  ];

  final int players;
  final DartsMode mode;
  final bool doubleOut;
  final List<DartsPlayerState> states;

  int current = 0;
  final List<DartHit> turnDarts = [];
  int _turnStart = 0;
  int? winner;
  bool lastTurnBust = false;
  int round = 1;

  bool get isOver => winner != null;
  DartsPlayerState get currentState => states[current];

  /// Next target number for "Rund um die Uhr".
  int targetOf(int player) =>
      clockTargets[min(states[player].remaining, clockTargets.length - 1)];

  /// Records a dart for the current player.
  void throwDart(DartHit hit) {
    if (isOver) return;
    final s = currentState;
    if (turnDarts.isEmpty) {
      _turnStart = s.remaining;
      lastTurnBust = false;
    }
    turnDarts.add(hit);
    s.darts++;
    if (mode == DartsMode.aroundTheClock) {
      if (!hit.isMiss && hit.value == targetOf(current)) {
        s.remaining++;
        if (s.remaining >= clockTargets.length) {
          winner = current;
          return;
        }
      }
    } else {
      final left = s.remaining - hit.points;
      final bust =
          left < 0 ||
          (doubleOut && (left == 1 || (left == 0 && !hit.isDouble)));
      if (bust) {
        s.scoredPoints -= _turnStart - s.remaining;
        s.remaining = _turnStart;
        lastTurnBust = true;
        _nextPlayer();
        return;
      }
      s.remaining = left;
      s.scoredPoints += hit.points;
      if (left == 0) {
        winner = current;
        return;
      }
    }
    if (turnDarts.length == 3) _nextPlayer();
  }

  void _nextPlayer() {
    turnDarts.clear();
    current = (current + 1) % players;
    if (current == 0) round++;
  }

  /// Darts thrown in the current turn (0..2), for display.
  int get dartsInTurn => turnDarts.length;
}
