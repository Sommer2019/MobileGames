// Rules of Mühle, Kniffel, Schach, Schiffe versenken and Solitär – the same
// as in the Flutter app (lib/games/...).
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <random>
#include <string>
#include <vector>

#include "logic.hpp"

// ---------------------------------------------------------------------- Mühle

// Points 0..23: three rings (outer 0–7, middle 8–15, inner 16–23), each
// clockwise from the top left corner. Odd points connect to the next ring.
class Mill {
 public:
  Mill();

  std::array<int, 24> board{};  // 0 empty, 1 white, 2 black
  std::array<int, 3> toPlace{0, 9, 9};
  int turn = 1;
  int winner = 0;
  bool draw = false;
  bool mustRemove = false;  // the player to move closed a mill
  int quietMoves = 0;
  int lastFrom = -1, lastTo = -1;

  static const std::vector<std::vector<int>>& neighbours();
  static const std::vector<std::array<int, 3>>& mills();

  bool isOver() const { return winner != 0 || draw; }
  bool placing(int p) const { return toPlace[p] > 0; }
  int stones(int p) const;
  bool canFly(int p) const { return !placing(p) && stones(p) == 3; }
  bool inMill(int point) const;
  std::vector<int> removable() const;
  bool canPlace(int point) const;
  std::vector<int> targets(int from) const;
  bool place(int point);
  bool move(int from, int to);
  bool remove(int point);

  struct Action {
    enum Kind { Place, Move, Remove } kind;
    int a, b;
  };
  std::optional<Action> aiAction(std::mt19937& rng) const;

 private:
  bool closesMill(int point, int player) const;
  void afterAction(int point);
  void endTurn();
  bool hasMove(int p) const;
  int threat(int point, int player) const;
};

// -------------------------------------------------------------------- Kniffel

enum KniffelCat {
  Ones, Twos, Threes, Fours, Fives, Sixes,
  ThreeKind, FourKind, FullHouse, SmallStraight, LargeStraight, Kniffel5, Chance,
  CatCount
};
const char* kniffelLabel(int cat);
int kniffelScore(int cat, const std::array<int, 5>& dice);

struct KniffelSheet {
  std::array<int, CatCount> entries;
  KniffelSheet() { entries.fill(-1); }
  bool filled(int c) const { return entries[c] >= 0; }
  bool complete() const;
  int upperSum() const;
  int bonus() const { return upperSum() >= 63 ? 35 : 0; }
  int lowerSum() const;
  int total() const { return upperSum() + bonus() + lowerSum(); }
};

class KniffelGame {
 public:
  KniffelGame(int players, uint32_t seed);
  int players;
  std::vector<KniffelSheet> sheets;
  std::array<int, 5> dice{1, 1, 1, 1, 1};
  std::array<bool, 5> held{};
  int rollsLeft = 3;
  int current = 0;

  bool hasRolled() const { return rollsLeft < 3; }
  bool canRoll() const { return rollsLeft > 0 && !isOver(); }
  bool isOver() const;
  void roll();
  void toggleHold(int i);
  bool canScore(int c) const { return hasRolled() && !sheets[current].filled(c); }
  bool score(int c);
  std::vector<int> winners() const;

  // Computer player: which dice to keep, which category to fill.
  std::array<bool, 5> aiHolds(std::mt19937& rng) const;
  int aiCategory() const;

 private:
  std::mt19937 rng_;
};

// --------------------------------------------------------------------- Schach

// Board index = rank * 8 + file, a1 = 0, h8 = 63. Pieces: 'P','N','B','R',
// 'Q','K' for white, lower case for black, 0 for empty.
struct ChessMove {
  int from, to;
  char promotion = 0;  // 'q', 'r', 'b', 'n' (lower case) or 0
};

// A position with the full rules (castling, en passant, promotion).
class ChessPos {
 public:
  ChessPos();
  std::array<char, 64> board{};
  bool whiteToMove = true;
  bool castleWK = true, castleWQ = true, castleBK = true, castleBQ = true;
  int epSquare = -1;  // square a pawn can capture onto en passant
  int halfmoves = 0;

  std::vector<ChessMove> legalMoves() const;
  bool hasLegalMove() const;
  bool inCheck() const;
  bool isWhite(int sq) const { return board[sq] >= 'A' && board[sq] <= 'Z'; }
  bool isPromotion(int from, int to) const;
  void apply(const ChessMove& m);  // no legality check
  bool insufficientMaterial() const;
  double material(bool white) const;
  std::string key() const;

 private:
  void pseudoMoves(std::vector<ChessMove>& out) const;
  bool attacked(int square, bool byWhite) const;
  int kingSquare(bool white) const;
  bool legal(const ChessMove& m) const;
};

// A game: position plus history (threefold repetition).
class Chess : public ChessPos {
 public:
  Chess();
  int lastFrom = -1, lastTo = -1;
  std::vector<ChessMove> movesFrom(int square) const;
  bool play(ChessMove m);  // false if illegal
  bool checkmate() const { return inCheck() && !hasLegalMove(); }
  bool stalemate() const { return !inCheck() && !hasLegalMove(); }
  bool draw() const;
  bool isOver() const { return checkmate() || draw(); }
  ChessMove aiMove(std::mt19937& rng) const;

 private:
  std::map<std::string, int> seen_;
};

// ------------------------------------------------------- Schiffe versenken

constexpr int SeaSize = 10;
const std::array<int, 5> FleetSizes{5, 4, 3, 3, 2};

enum class Shot { Miss, Hit, Sunk };
enum class Mark : uint8_t { Unknown, Miss, Hit, Sunk };

struct Ship {
  std::vector<Cell> cells;  // (x, y)
  std::vector<Cell> hits;
  bool sunk() const { return hits.size() == cells.size(); }
};

class Fleet {
 public:
  std::vector<Ship> ships;
  std::vector<Cell> shots;  // received
  const Ship* shipAt(int x, int y) const;
  bool canPlace(const std::vector<Cell>& cells) const;
  bool place(int x, int y, int len, bool horizontal);
  static Fleet random(std::mt19937& rng);
  bool allSunk() const;
  bool shotAt(int x, int y) const;
  // Returns the result; for a sunk ship [sunkCells] lists its cells.
  Shot receive(int x, int y, std::vector<Cell>* sunkCells);
};

struct Chart {  // what a player knows about the other fleet
  std::array<std::array<Mark, SeaSize>, SeaSize> cells{};  // [y][x]
  bool canShoot(int x, int y) const { return cells[y][x] == Mark::Unknown; }
  void apply(int x, int y, Shot s, const std::vector<Cell>& sunk);
};

Cell battleshipAiShot(const Chart& knowledge, std::mt19937& rng);

// -------------------------------------------------------------------- Solitär

struct Card {
  int suit;  // 0 ♠, 1 ♥, 2 ♦, 3 ♣
  int rank;  // 1 = Ass … 13 = König
  bool faceUp = false;
  bool red() const { return suit == 1 || suit == 2; }
};

enum class PileKind { Stock, Waste, Foundation, Tableau };
struct PileRef {
  PileKind kind;
  int index = 0;
  bool operator==(const PileRef& o) const { return kind == o.kind && index == o.index; }
};

class Klondike {
 public:
  Klondike(int drawCount, uint32_t seed);
  int drawCount;
  std::vector<Card> stock, waste;
  std::array<std::vector<Card>, 4> foundations;
  std::array<std::vector<Card>, 7> tableau;
  int moves = 0, score = 0;

  bool won() const;
  std::vector<Card>& pile(PileRef p);
  const std::vector<Card>& pile(PileRef p) const;
  bool canMove(PileRef from, int index, PileRef to) const;
  bool move(PileRef from, int index, PileRef to);
  bool draw();
  bool undo();
  bool canUndo() const { return !history_.empty(); }
  std::optional<PileRef> bestTarget(PileRef from, int index) const;
  bool canAutoComplete() const;
  bool autoStep();

 private:
  bool movable(PileRef from, int index) const;
  bool onTableau(const Card& c, int t) const;
  bool onFoundation(const Card& c, int f) const;
  void addScore(int p) { score = std::max(0, score + p); }
  struct Snapshot {
    std::vector<Card> stock, waste;
    std::array<std::vector<Card>, 4> foundations;
    std::array<std::vector<Card>, 7> tableau;
    int moves, score;
  };
  void save();
  std::vector<Snapshot> history_;
};
