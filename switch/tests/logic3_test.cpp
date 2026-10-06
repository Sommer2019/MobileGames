// Rule and physics tests for Mahjong, Labyrinth, Darts and Billard.
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "logic3.hpp"

static int failures = 0;
#define CHECK(cond)                                                \
  do {                                                             \
    if (!(cond)) {                                                 \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
      failures++;                                                  \
    }                                                              \
  } while (0)

static void mahjong() {
  for (auto layout : {mahjongPyramid(), mahjongTower()}) {
    CHECK(layout.size() % 2 == 0);
    Mahjong m(layout, 3);
    CHECK(m.remaining() == (int)layout.size());
    CHECK(m.hint().has_value());
    // Every face appears an even number of times.
    for (size_t i = 0; i < m.faces.size(); i++) {
      int n = 0;
      for (auto& f : m.faces) n += f == m.faces[i];
      CHECK(n % 2 == 0);
    }
    auto [a, b] = *m.hint();
    CHECK(m.match(a, b));
    CHECK(m.remaining() == (int)layout.size() - 2);
    CHECK(m.undo());
    CHECK(m.remaining() == (int)layout.size());
  }
  // A covered tile is not free.
  Mahjong p(mahjongPyramid(), 1);
  CHECK(!p.isFree(13));  // second row, under the second layer
}

static void labyrinth() {
  CHECK(labyrinthLevelCount() == 26);
  for (int i = 0; i < labyrinthLevelCount(); i++) {
    LLevel l = labyrinthLevel(i);
    CHECK(!l.name.empty());
    Labyrinth g(l);
    g.step(0.02, 0, 0);
    CHECK(g.state == BallState::Rolling);  // the start is safe
  }
  // Level 1: tilting right first rolls into the first wall's gap side.
  Labyrinth g(labyrinthLevel(0));
  for (int i = 0; i < 200; i++) g.step(0.016, 1, 0);
  CHECK(g.x > 0.8 && g.state == BallState::Rolling);  // stopped by the frame
  // A ball falls through a hole.
  LLevel hole{"t", 0.5, 0.5, {0.9, 1.5}, {}, {{0.5, 0.7, 0.05}}, true};
  Labyrinth h(hole);
  for (int i = 0; i < 200 && h.state == BallState::Rolling; i++) h.step(0.016, 0, 1);
  CHECK(h.state == BallState::Fell);
}

static void darts() {
  using namespace dartboard;
  CHECK(score(0, 0).label() == "Bull");
  CHECK(score(0, -103).label() == "T20");
  CHECK(score(0, -166).label() == "D20");
  CHECK(score(0, 103).label() == "T3");
  CHECK(score(0, -200).miss());
  CHECK(score(103, 0).value == 6);

  Darts d(1, DartsMode::X301);
  d.states[0].remaining = 40;
  d.throwDart({20, 1});   // 20 left
  d.throwDart({19, 1});   // 1 left -> bust (double out)
  CHECK(d.lastBust && d.states[0].remaining == 40 && d.turn.empty());
  d.throwDart({20, 2});
  CHECK(d.winner == 0);

  Darts c(2, DartsMode::Clock);
  c.throwDart({1, 3});
  CHECK(c.states[0].remaining == 1 && c.target(0) == 2);
  c.throwDart({5, 1});
  c.throwDart({2, 1});
  CHECK(c.current == 1);
}

static void billiard() {
  Billiard g;
  CHECK(g.balls.size() == 16 && g.remaining() == 15);
  CHECK(g.shoot(0, 1.0));
  for (int i = 0; i < 2000 && g.moving(); i++) g.step(0.016);
  CHECK(!g.moving());
  CHECK(g.firstHit >= 1);
  // Balls stay on the table and do not overlap.
  for (size_t i = 0; i < g.balls.size(); i++) {
    const auto& a = g.balls[i];
    if (a.pocketed) continue;
    CHECK(a.x >= 0 && a.x <= Billiard::W && a.y >= 0 && a.y <= Billiard::H);
    for (size_t j = i + 1; j < g.balls.size(); j++) {
      const auto& b = g.balls[j];
      if (!b.pocketed) CHECK(std::hypot(a.x - b.x, a.y - b.y) > Billiard::Radius * 1.9);
    }
  }
  // Straight into a corner pocket.
  Billiard p;
  for (size_t i = 1; i < p.balls.size(); i++) p.balls[i].pocketed = true;
  p.balls[1] = {1, 1.8, 0.8};
  p.cue().x = 1.0;
  p.cue().y = 0.0 + 0.5 - 0.5 * (1.0 / 1.0) + 0.5 - 0.5 + 0.3;  // 0.3
  const double ang = std::atan2(p.balls[1].y - p.cue().y, p.balls[1].x - p.cue().x);
  // Aim so the object ball heads to the corner (2, 1).
  const double tx = Billiard::W, ty = Billiard::H;
  const double gx = p.balls[1].x - std::cos(std::atan2(ty - p.balls[1].y, tx - p.balls[1].x)) * Billiard::Radius * 2;
  const double gy = p.balls[1].y - std::sin(std::atan2(ty - p.balls[1].y, tx - p.balls[1].x)) * Billiard::Radius * 2;
  (void)ang;
  p.shoot(std::atan2(gy - p.cue().y, gx - p.cue().x), 0.6);
  for (int i = 0; i < 2000 && p.moving(); i++) p.step(0.016);
  CHECK(p.won());

  // 8-ball rules.
  EightBall r;
  r.evaluate({3}, 3, false, false);
  CHECK(r.groups[0] == Group::Solids && r.groups[1] == Group::Stripes && r.current == 0);
  r.evaluate({}, 12, false, false);  // wrong ball first
  CHECK(r.current == 1);
  r.evaluate({8}, 8, false, false);  // eight too early
  CHECK(r.winner == 0);

  SoloRules s(SoloMode::Rotation);
  s.evaluate({}, 5, false, 14, 1);
  CHECK(s.penalties == 1);
}

int main() {
  mahjong();
  labyrinth();
  darts();
  billiard();
  if (failures) {
    std::printf("%d check(s) failed\n", failures);
    return EXIT_FAILURE;
  }
  std::printf("All checks passed\n");
  return EXIT_SUCCESS;
}
