// Rule tests for Mühle, Kniffel, Schach, Schiffe versenken and Solitär.
#include <cstdio>
#include <cstdlib>
#include <random>

#include "logic2.hpp"

static int failures = 0;
#define CHECK(cond)                                                \
  do {                                                             \
    if (!(cond)) {                                                 \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      failures++;                                                  \
    }                                                              \
  } while (0)

static void mill() {
  Mill g;
  // White builds the top row of the outer ring (0, 1, 2).
  CHECK(g.place(0));
  CHECK(g.place(8));
  CHECK(g.place(1));
  CHECK(g.place(9));
  CHECK(g.place(2));
  CHECK(g.mustRemove);
  // Stones in a mill are protected while others exist.
  CHECK(g.remove(8));
  CHECK(!g.mustRemove && g.turn == 2);
  CHECK(Mill::neighbours()[1].size() == 3);
  CHECK(Mill::mills().size() == 16);

  // The computer closes its own mill.
  Mill ai;
  ai.place(16);
  ai.place(0);
  ai.place(17);
  ai.place(4);
  std::mt19937 rng(1);
  auto a = ai.aiAction(rng);
  CHECK(a && a->kind == Mill::Action::Place && a->a == 18);
}

static void kniffel() {
  CHECK(kniffelScore(FullHouse, {2, 2, 3, 3, 3}) == 25);
  CHECK(kniffelScore(FullHouse, {3, 3, 3, 3, 3}) == 0);
  CHECK(kniffelScore(SmallStraight, {1, 2, 3, 4, 6}) == 30);
  CHECK(kniffelScore(LargeStraight, {2, 3, 4, 5, 6}) == 40);
  CHECK(kniffelScore(Kniffel5, {4, 4, 4, 4, 4}) == 50);
  CHECK(kniffelScore(Threes, {3, 3, 1, 3, 6}) == 9);
  CHECK(kniffelScore(FourKind, {5, 5, 5, 5, 1}) == 21);
  CHECK(kniffelScore(Chance, {1, 2, 3, 4, 5}) == 15);

  KniffelGame g(2, 3);
  CHECK(!g.canScore(Chance));
  g.roll();
  CHECK(g.rollsLeft == 2);
  CHECK(g.score(Chance));
  CHECK(g.current == 1 && g.rollsLeft == 3);
  KniffelSheet s;
  for (int c = Ones; c <= Sixes; c++) s.entries[c] = (c + 1) * 3;
  CHECK(s.upperSum() == 63 && s.bonus() == 35);

  std::mt19937 rng(5);
  KniffelGame ai(1, 9);
  ai.roll();
  ai.dice = {6, 6, 6, 6, 2};
  auto holds = ai.aiHolds(rng);
  CHECK(holds[0] && holds[1] && holds[2] && holds[3]);
}

static long perft(const ChessPos& p, int depth) {
  if (depth == 0) return 1;
  long n = 0;
  for (auto& m : p.legalMoves()) {
    ChessPos c = p;
    c.apply(m);
    n += perft(c, depth - 1);
  }
  return n;
}

static int sq(const char* s) { return (s[1] - '1') * 8 + (s[0] - 'a'); }

static void chess() {
  Chess g;
  CHECK(g.legalMoves().size() == 20);
  CHECK(perft(g, 3) == 8902);

  // "Kiwipete": castling, en passant and promotions (perft 2 = 2039).
  ChessPos k;
  k.board.fill(0);
  const char* rows[8] = {"r...k..r", "p.ppqpb.", "bn..pnp.", "...PN...",
                         ".p..P...", "..N..Q.p", "PPPBBPPP", "R...K..R"};
  for (int r = 0; r < 8; r++) {
    for (int f = 0; f < 8; f++) {
      const char c = rows[r][f];
      k.board[(7 - r) * 8 + f] = c == '.' ? 0 : c;
    }
  }
  CHECK(k.legalMoves().size() == 48);
  CHECK(perft(k, 2) == 2039);

  // Fool's mate.
  Chess fool;
  CHECK(fool.play({sq("f2"), sq("f3")}));
  CHECK(fool.play({sq("e7"), sq("e5")}));
  CHECK(fool.play({sq("g2"), sq("g4")}));
  CHECK(fool.play({sq("d8"), sq("h4")}));
  CHECK(fool.checkmate());
  CHECK(!fool.play({sq("a2"), sq("a3")}));

  // En passant.
  Chess ep;
  ep.play({sq("e2"), sq("e4")});
  ep.play({sq("a7"), sq("a6")});
  ep.play({sq("e4"), sq("e5")});
  ep.play({sq("d7"), sq("d5")});
  CHECK(ep.play({sq("e5"), sq("d6")}));
  CHECK(ep.board[sq("d5")] == 0 && ep.board[sq("d6")] == 'P');

  // The computer takes a free queen.
  Chess free;
  free.play({sq("e2"), sq("e4")});
  free.play({sq("d8"), sq("d8")});  // illegal, ignored
  free.play({sq("d7"), sq("d5")});
  free.play({sq("d1"), sq("g4")});
  std::mt19937 rng(2);
  ChessMove m = free.aiMove(rng);
  CHECK(m.from == sq("c8") && m.to == sq("g4"));
}

static void battleship() {
  std::mt19937 rng(4);
  Fleet f = Fleet::random(rng);
  int cells = 0;
  for (auto& s : f.ships) cells += int(s.cells.size());
  CHECK(f.ships.size() == 5 && cells == 17);
  Fleet b;
  CHECK(b.place(0, 0, 3, true));
  CHECK(!b.place(1, 1, 2, false));  // touches diagonally
  std::vector<Cell> sunk;
  CHECK(b.receive(5, 5, &sunk) == Shot::Miss);
  CHECK(b.receive(0, 0, &sunk) == Shot::Hit);
  CHECK(b.receive(1, 0, &sunk) == Shot::Hit);
  CHECK(b.receive(2, 0, &sunk) == Shot::Sunk);
  CHECK(sunk.size() == 3 && b.allSunk());
  Chart c;
  c.apply(0, 0, Shot::Sunk, sunk);
  CHECK(c.cells[1][0] == Mark::Miss && c.cells[0][1] == Mark::Sunk);
  Chart hunt;
  hunt.apply(4, 4, Shot::Hit, {});
  auto [x, y] = battleshipAiShot(hunt, rng);
  CHECK(std::abs(x - 4) + std::abs(y - 4) == 1);
}

static void solitaire() {
  Klondike k(1, 42);
  int total = int(k.stock.size());
  for (auto& t : k.tableau) total += int(t.size());
  CHECK(total == 52);
  CHECK(k.tableau[6].size() == 7 && k.tableau[6].back().faceUp);
  CHECK(!k.tableau[6].front().faceUp);
  CHECK(k.draw());
  CHECK(k.waste.size() == 1 && k.stock.size() == 23);
  CHECK(k.undo());
  CHECK(k.waste.empty() && k.stock.size() == 24);

  Klondike m(1, 1);
  for (auto& t : m.tableau) t.clear();
  m.stock.clear();
  m.tableau[0] = {{0, 13, true}};          // ♠ K
  m.tableau[1] = {{1, 12, true}};          // ♥ D
  m.tableau[2] = {{1, 1, true}};           // ♥ A
  CHECK(m.canMove({PileKind::Tableau, 1}, 0, {PileKind::Tableau, 0}));
  CHECK(!m.canMove({PileKind::Tableau, 0}, 0, {PileKind::Tableau, 1}));
  auto t = m.bestTarget({PileKind::Tableau, 2}, 0);
  CHECK(t && t->kind == PileKind::Foundation);
}

int main() {
  mill();
  kniffel();
  chess();
  battleship();
  solitaire();
  if (failures) {
    std::printf("%d check(s) failed\n", failures);
    return EXIT_FAILURE;
  }
  std::printf("All checks passed\n");
  return EXIT_SUCCESS;
}
