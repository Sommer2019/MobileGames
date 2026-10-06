// Rules and physics of Mahjong, Labyrinth, Darts and Billard – the same as
// in the Flutter app (lib/games/...).
#pragma once

#include <optional>
#include <random>
#include <string>
#include <utility>
#include <vector>

// -------------------------------------------------------------------- Mahjong

struct MjSlot {
  int x, y, z;  // a tile covers 2×2 units
};

// suit 0..2 = Zahlen/Kreise/Bambus (rank 0..8), 3 = Winde (0..3),
// 4 = Drachen (0..2).
struct MjFace {
  int suit = 0, rank = 0;
  bool operator==(const MjFace& o) const { return suit == o.suit && rank == o.rank; }
};

std::vector<MjSlot> mahjongPyramid();
std::vector<MjSlot> mahjongTower();

class Mahjong {
 public:
  Mahjong(std::vector<MjSlot> layout, uint32_t seed);
  std::vector<MjSlot> slots;
  std::vector<MjFace> faces;
  std::vector<bool> removed;
  std::vector<std::pair<int, int>> history;

  int remaining() const;
  bool won() const { return remaining() == 0; }
  bool isFree(int i) const;
  bool canMatch(int a, int b) const;
  bool match(int a, int b);
  bool undo();
  std::optional<std::pair<int, int>> hint() const;
  bool stuck() const { return !won() && !hint(); }
  void shuffleRemaining(std::mt19937& rng);
};

// ------------------------------------------------------------------ Labyrinth

struct LWall {
  double left, top, right, bottom;
};
struct LHole {
  double x, y, radius = 0.045;
};
struct LLevel {
  std::string name;
  double startX, startY;
  LHole goal;
  std::vector<LWall> walls;
  std::vector<LHole> holes;
  bool frame = true;
};

constexpr double BoardW = 1.0, BoardH = 1.6;
int labyrinthLevelCount();
LLevel labyrinthLevel(int i);

enum class BallState { Rolling, Fell, Won };

class Labyrinth {
 public:
  explicit Labyrinth(LLevel level);
  static constexpr double Radius = 0.03, Gravity = 2.2;
  LLevel level;
  double x = 0, y = 0, vx = 0, vy = 0;
  double elapsed = 0;
  BallState state = BallState::Rolling;
  void reset();
  // tiltX/tiltY in -1..1 (board coordinates).
  void step(double dt, double tiltX, double tiltY);

 private:
  void collide(const LWall& w);
  void checkHoles();
};

// ---------------------------------------------------------------------- Darts

struct DartHit {
  int value = 0;       // 1..20, 25 = bull, 0 = miss
  int multiplier = 0;  // 0 = miss
  int points() const { return value * multiplier; }
  bool miss() const { return multiplier == 0; }
  std::string label() const;
};

namespace dartboard {
constexpr double BullInner = 6.35, BullOuter = 15.9, TripleInner = 99, TripleOuter = 107,
                 DoubleInner = 162, DoubleOuter = 170;
extern const int Numbers[20];
DartHit score(double x, double y);  // millimetres from the centre, y down
}  // namespace dartboard

enum class DartsMode { X501, X301, Clock };

struct DartsPlayer {
  int remaining = 0;  // X01: points left; clock: index of the next target
  int darts = 0;
  int scored = 0;
  double average() const { return darts ? scored * 3.0 / darts : 0; }
};

class Darts {
 public:
  Darts(int players, DartsMode mode, bool doubleOut = true);
  int players;
  DartsMode mode;
  bool doubleOut;
  std::vector<DartsPlayer> states;
  int current = 0;
  std::vector<DartHit> turn;
  int winner = -1;
  bool lastBust = false;
  int round = 1;

  bool isOver() const { return winner >= 0; }
  int target(int player) const;
  void throwDart(const DartHit& hit);

 private:
  void next();
  int turnStart_ = 0;
};

// -------------------------------------------------------------------- Billard

struct PoolBall {
  int number;  // 0 = cue ball
  double x, y, vx = 0, vy = 0;
  bool pocketed = false;
  bool moving() const { return vx * vx + vy * vy > 1e-8; }
};

class Billiard {
 public:
  Billiard();
  static constexpr double W = 2.0, H = 1.0, Radius = 0.028, PocketRadius = 0.062,
                          Friction = 0.45, Cushion = 0.8, MaxSpeed = 4.0;
  static const double Pockets[6][2];

  std::vector<PoolBall> balls;
  int shots = 0, fouls = 0;
  std::vector<int> pocketedThisShot;
  int firstHit = -1;  // -1 = nothing hit yet
  bool scratched = false;
  bool cueInHand = true;

  PoolBall& cue() { return balls.front(); }
  const PoolBall& cue() const { return balls.front(); }
  bool moving() const;
  int remaining() const;
  bool won() const { return remaining() == 0; }
  bool shoot(double angle, double power, double spin = 0);
  void step(double dt);
  bool placeCue(double x, double y);

  // Where the cue ball would touch the first ball (or cushion).
  struct Preview {
    double x, y;
    int ball = -1;            // index into balls, -1 = cushion
    double dirX = 0, dirY = 0;  // where the hit ball goes
  };
  Preview preview(double angle) const;

 private:
  void substep(double h);
  void collide(PoolBall& a, PoolBall& b);
  void respawnCue();
  double spin_ = 0, dirX_ = 1, dirY_ = 0;
};

enum class Group { None, Solids, Stripes };
Group groupOf(int n);

// 8-ball for two players.
struct EightBall {
  int current = 0;
  Group groups[2] = {Group::None, Group::None};
  int winner = -1;
  std::string lastEvent;
  int remainingOf(const Billiard& g, int player) const;
  void evaluate(const std::vector<int>& pocketed, int firstHit, bool scratched,
                bool clearedBefore);
};

enum class SoloMode { EightLast, Rotation };

struct SoloRules {
  explicit SoloRules(SoloMode m) : mode(m) {}
  SoloMode mode;
  bool lost = false;
  int penalties = 0;
  std::string lastEvent;
  int target(const Billiard& g) const;  // -1 = none
  static int othersLeft(const Billiard& g);
  void evaluate(const std::vector<int>& pocketed, int firstHit, bool scratched,
                int othersBefore, int targetBefore);
};
