// Game rules of the Switch version, the same as in the Flutter app
// (lib/games/...). No rendering here, so they can be tested on a PC.
#pragma once

#include <array>
#include <cstdint>
#include <deque>
#include <random>
#include <utility>
#include <vector>

using Cell = std::pair<int, int>;  // (row, col) or (x, y)

// ------------------------------------------------------------------ 4 gewinnt

// Connect Four for 2–4 players; with more players the board grows.
class ConnectFour {
 public:
  explicit ConnectFour(int players = 2);

  int players, columns, rows;
  std::vector<std::vector<int>> board;  // [row][col], row 0 on top; 0 = empty
  int current = 1;
  int winner = 0;
  bool draw = false;
  std::vector<Cell> winningCells;

  bool isOver() const { return winner != 0 || draw; }
  bool canDrop(int col) const;
  // Drops a disc for the current player; returns the row or -1.
  int drop(int col);
  // Best column for the current player (minimax, like the app).
  int aiMove(int depth = 5) const;

 private:
  bool findLine(int row, int col, std::vector<Cell>* cells) const;
  int minimax(int depth, int alpha, int beta, int me) const;
  int evaluate(int me) const;
  std::vector<int> order() const;
};

// ----------------------------------------------------------------------- Dame

enum class Side : uint8_t { White, Black };

struct Piece {
  bool present = false;
  Side side = Side::White;
  bool king = false;
};

struct CheckersMove {
  std::vector<Cell> path;  // start, landing squares …
  std::vector<Cell> captured;
  Cell from() const { return path.front(); }
  Cell to() const { return path.back(); }
};

// German draughts: men move and capture forward only, capturing is
// mandatory and multi-captures must be completed, kings fly. Whoever
// cannot move loses; 50 king moves without capture are a draw.
class Checkers {
 public:
  Checkers();

  std::array<std::array<Piece, 8>, 8> board{};  // row 0 = black's home row
  Side turn = Side::White;
  bool hasWinner = false;
  Side winner = Side::White;
  bool draw = false;
  int quietMoves = 0;
  std::vector<Cell> lastPath;

  bool isOver() const { return hasWinner || draw; }
  std::vector<CheckersMove> legalMoves() const;
  void apply(const CheckersMove& m);
  // Simple computer player (prefers captures, avoids giving any).
  CheckersMove aiMove(std::mt19937& rng) const;

 private:
  static bool inside(int r, int c) { return r >= 0 && r < 8 && c >= 0 && c < 8; }
  static int forward(Side s) { return s == Side::White ? -1 : 1; }
  void captures(int r, int c, const Piece& p, std::vector<Cell>& path,
                std::vector<Cell>& taken, std::vector<CheckersMove>& out) const;
  void quiet(int r, int c, const Piece& p, std::vector<CheckersMove>& out) const;
};

// ---------------------------------------------------------------------- Snake

enum class Dir : uint8_t { Up, Down, Left, Right };

class Snake {
 public:
  Snake(int width, int height, bool wrap, uint32_t seed);

  int width, height;
  bool wrap;
  std::deque<Cell> body;  // (x, y), front is the head
  Dir direction = Dir::Up;
  Cell food{0, 0};
  int score = 0;
  bool dead = false;

  bool won() const { return (int)body.size() == width * height; }
  // Steps per second; grows with the score.
  double speed() const;
  // Queues a turn; two quick turns within one step both count.
  void turn(Dir d);
  void step();

 private:
  std::vector<Dir> queue_;
  std::mt19937 rng_;
  void placeFood();
};

// ------------------------------------------------------------------ Schütteln

// Detects shaking from accelerometer samples (m/s², gravity included –
// it is filtered out). A shake is several strong movements within a short
// window, like in the app.
class ShakeDetector {
 public:
  // Feeds one sample at [time] seconds; true when a shake is recognised.
  bool add(double x, double y, double z, double time);

 private:
  static constexpr double Threshold = 12, Window = 0.7, Cooldown = 1.2;
  static constexpr int MinPeaks = 3;
  bool hasGravity_ = false;
  double gx_ = 0, gy_ = 0, gz_ = 0;
  std::vector<double> peaks_;
  double lastShake_ = -1e9;
};

// ----------------------------------------------------------------- Würfel

struct DiceCup {
  int count = 2;
  std::array<int, 6> values{1, 1, 1, 1, 1, 1};
  std::array<bool, 6> held{};
  // Last rolls (newest first): the values of all dice of that roll.
  std::deque<std::vector<int>> history;

  int sum() const;
  void roll(std::mt19937& rng);
};
