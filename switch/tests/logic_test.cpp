// Rule tests for the Switch version (run on the PC: make -f Makefile.pc test).
#include <cstdio>
#include <cstdlib>
#include <random>

#include "logic.hpp"

static int failures = 0;
#define CHECK(cond)                                                   \
  do {                                                                \
    if (!(cond)) {                                                    \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);    \
      failures++;                                                     \
    }                                                                 \
  } while (0)

static void connectFour() {
  ConnectFour g;
  CHECK(g.columns == 7 && g.rows == 6);
  // Red builds a row at the bottom, yellow plays on top.
  for (int c : {0, 0, 1, 1, 2, 2}) g.drop(c);
  CHECK(!g.isOver());
  g.drop(3);
  CHECK(g.winner == 1);
  CHECK(g.winningCells.size() == 4);
  CHECK(g.drop(4) == -1);  // game over

  ConnectFour four(4);
  CHECK(four.columns == 10 && four.rows == 8);
  four.drop(0);
  CHECK(four.current == 2);
  four.drop(0);
  four.drop(0);
  four.drop(0);
  CHECK(four.current == 1);

  // The computer completes its own three in a row.
  ConnectFour ai;
  for (int c : {0, 6, 1, 6, 2}) ai.drop(c);
  ai.current = 1;
  CHECK(ai.aiMove() == 3);
  // … and blocks the opponent.
  ConnectFour block;
  for (int c : {0, 6, 1, 6, 2}) block.drop(c);
  CHECK(block.current == 2);
  CHECK(block.aiMove() == 3);

  // A full column takes no more discs.
  ConnectFour full;
  for (int i = 0; i < 6; i++) full.drop(5);
  CHECK(!full.canDrop(5));
}

static Checkers empty() {
  Checkers g;
  for (auto& row : g.board) {
    for (auto& p : row) p = {};
  }
  return g;
}

static void checkers() {
  Checkers g;
  // White starts with 7 quiet moves (four men in the front row).
  CHECK(g.legalMoves().size() == 7);

  // Capturing is mandatory.
  Checkers c = empty();
  c.board[5][2] = {true, Side::White, false};
  c.board[4][3] = {true, Side::Black, false};
  c.board[0][7] = {true, Side::Black, false};
  c.board[6][7] = {true, Side::White, false};
  auto moves = c.legalMoves();
  CHECK(moves.size() == 1);
  CHECK(moves[0].captured.size() == 1);
  CHECK(moves[0].to() == Cell(3, 4));

  // Men do not capture backwards.
  Checkers back = empty();
  back.board[3][2] = {true, Side::White, false};
  back.board[4][3] = {true, Side::Black, false};
  back.board[0][7] = {true, Side::Black, false};
  for (auto& m : back.legalMoves()) CHECK(m.captured.empty());

  // Multi-captures are completed.
  Checkers multi = empty();
  multi.board[7][0] = {true, Side::White, false};
  multi.board[6][1] = {true, Side::Black, false};
  multi.board[4][3] = {true, Side::Black, false};
  multi.board[0][7] = {true, Side::Black, false};
  moves = multi.legalMoves();
  CHECK(moves.size() == 1);
  CHECK(moves[0].captured.size() == 2);
  CHECK(moves[0].to() == Cell(3, 4));

  // Kings fly: capture from a distance and land anywhere behind.
  Checkers king = empty();
  king.board[7][0] = {true, Side::White, true};
  king.board[4][3] = {true, Side::Black, false};
  king.board[0][1] = {true, Side::Black, false};
  moves = king.legalMoves();
  CHECK(moves.size() == 4);  // lands on (3,4), (2,5), (1,6), (0,7)
  for (auto& m : moves) CHECK(m.captured.size() == 1);

  // Reaching the last row promotes; no moves left means a loss.
  Checkers promo = empty();
  promo.board[1][0] = {true, Side::White, false};
  promo.board[7][7] = {true, Side::Black, false};
  promo.apply(promo.legalMoves()[0]);
  CHECK(promo.board[0][1].king);
  CHECK(promo.hasWinner && promo.winner == Side::White);

  // The computer takes the capture.
  std::mt19937 rng(1);
  Checkers ai = empty();
  ai.turn = Side::Black;
  ai.board[2][1] = {true, Side::Black, false};
  ai.board[3][2] = {true, Side::White, false};
  ai.board[7][6] = {true, Side::White, false};
  CHECK(!ai.aiMove(rng).captured.empty());
  CHECK(!ai.strongMove(rng).captured.empty());
  // The strong computer plays a full opening move quickly enough.
  Checkers start;
  CHECK(!start.strongMove(rng).path.empty());
}

static void snake() {
  Snake s(10, 10, false, 1);
  s.food = {0, 0};
  const Cell head = s.body.front();
  s.step();
  CHECK(s.body.front() == Cell(head.first, head.second - 1));
  s.turn(Dir::Down);  // reversing is ignored
  s.step();
  CHECK(s.direction == Dir::Up);
  // Two quick turns within one step both count.
  s.turn(Dir::Left);
  s.turn(Dir::Down);
  const Cell before = s.body.front();
  s.step();
  s.step();
  CHECK(s.body.front() == Cell(before.first - 1, before.second + 1));
  CHECK(!s.dead);

  Snake wall(10, 10, false, 2);
  wall.food = {9, 9};
  for (int i = 0; i < 10; i++) wall.step();
  CHECK(wall.dead);

  Snake wrap(10, 10, true, 3);
  wrap.food = {9, 9};
  for (int i = 0; i < 12; i++) wrap.step();
  CHECK(!wrap.dead);

  Snake eat(10, 10, false, 4);
  const auto [x, y] = eat.body.front();
  eat.food = {x, y - 1};
  const size_t len = eat.body.size();
  eat.step();
  CHECK(eat.body.size() == len + 1);
  CHECK(eat.score == 1);
  CHECK(eat.speed() > 6);
}

static void dice() {
  std::mt19937 rng(7);
  DiceCup cup;
  cup.count = 3;
  cup.values = {6, 6, 6, 1, 1, 1};
  cup.held[0] = true;
  for (int i = 0; i < 12; i++) cup.roll(rng);
  CHECK(cup.values[0] == 6);  // set aside, never rolled
  CHECK(cup.history.size() == 10);
  CHECK(cup.history.front().size() == 3);
  for (int i = 0; i < 3; i++) CHECK(cup.values[i] >= 1 && cup.values[i] <= 6);
  CHECK(cup.sum() == cup.values[0] + cup.values[1] + cup.values[2]);
}

static void shake() {
  ShakeDetector d;
  double t = 0;
  // Lying still: no shake.
  bool any = false;
  for (int i = 0; i < 100; i++, t += 0.016) any |= d.add(0, 0, 9.81, t);
  CHECK(!any);
  // Shaking: strong back-and-forth movements.
  bool shaken = false;
  for (int i = 0; i < 30 && !shaken; i++, t += 0.016) {
    shaken = d.add(i % 2 ? 25 : -25, 0, 9.81, t);
  }
  CHECK(shaken);
  // Cooldown: not again right away.
  CHECK(!d.add(25, 0, 9.81, t + 0.02) && !d.add(-25, 0, 9.81, t + 0.04) &&
        !d.add(25, 0, 9.81, t + 0.06));
}

int main() {
  shake();
  connectFour();
  checkers();
  snake();
  dice();
  if (failures) {
    std::printf("%d check(s) failed\n", failures);
    return EXIT_FAILURE;
  }
  std::printf("All checks passed\n");
  return EXIT_SUCCESS;
}
