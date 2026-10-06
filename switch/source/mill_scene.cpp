#include <algorithm>
#include <cmath>
#include <ctime>
#include <random>
#include <string>

#include "logic2.hpp"
#include "scene.hpp"

namespace {

constexpr int CX = Gfx::W / 2, CY = 372;

// Screen position of a point (rings clockwise from the top left corner).
std::pair<int, int> pointPos(int i) {
  static const int half[3] = {250, 167, 84};
  static const int dx[8] = {-1, 0, 1, 1, 1, 0, -1, -1};
  static const int dy[8] = {-1, -1, -1, 0, 1, 1, 1, 0};
  const int h = half[i / 8];
  return {CX + dx[i % 8] * h, CY + dy[i % 8] * h};
}

class MillScene : public Scene {
 public:
  explicit MillScene(bool vsComputer)
      : vsComputer_(vsComputer), rng_(uint32_t(std::time(nullptr))) {}

  void update(const Input& in, double dt) override {
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (game_.isOver()) {
      if (in[BtnA]) restart();
      if (in[BtnB]) done = true;
      return;
    }
    if (computerTurn()) {
      thinking_ += dt;
      if (thinking_ > 0.6) {
        thinking_ = 0;
        if (auto a = game_.aiAction(rng_)) {
          if (a->kind == Mill::Action::Place) game_.place(a->a);
          if (a->kind == Mill::Action::Move) game_.move(a->a, a->b);
          if (a->kind == Mill::Action::Remove) game_.remove(a->a);
        }
      }
      return;
    }
    if (in[BtnUp]) step(0, -1);
    if (in[BtnDown]) step(0, 1);
    if (in[BtnLeft]) step(-1, 0);
    if (in[BtnRight]) step(1, 0);
    if (in.tapped) {
      for (int i = 0; i < 24; i++) {
        auto [x, y] = pointPos(i);
        if (std::hypot(in.tapX - x, in.tapY - y) < 40) {
          cursor_ = i;
          choose(i);
          return;
        }
      }
    }
    if (in[BtnA]) choose(cursor_);
    if (in[BtnB]) {
      if (selected_ >= 0) {
        selected_ = -1;
      } else {
        done = true;
      }
    }
  }

  void draw(Gfx& g) override {
    g.header("Mühle", "Weiß " + count(1) + "  ·  Schwarz " + count(2));
    const Color line = rgb(0x5D4037);
    g.roundRect(CX - 282, CY - 282, 564, 564, 24, rgb(0xE6C99A));
    for (int ring = 0; ring < 3; ring++) {
      for (int i = 0; i < 8; i++) {
        auto [x1, y1] = pointPos(ring * 8 + i);
        auto [x2, y2] = pointPos(ring * 8 + (i + 1) % 8);
        thick(g, x1, y1, x2, y2, line);
      }
    }
    for (int k : {1, 3, 5, 7}) {
      auto [x1, y1] = pointPos(k);
      auto [x2, y2] = pointPos(k + 16);
      thick(g, x1, y1, x2, y2, line);
    }
    const auto hints = highlights();
    for (int i = 0; i < 24; i++) {
      auto [x, y] = pointPos(i);
      g.circle(x, y, 9, line);
      if (i == game_.lastTo || i == game_.lastFrom) g.ring(x, y, 32, 3, rgb(0x8D6E63));
      if (std::find(hints.begin(), hints.end(), i) != hints.end()) {
        g.circle(x, y, 12, game_.mustRemove ? rgb(0xE53935) : rgb(0x7CB342));
      }
      const int p = game_.board[i];
      if (p) {
        g.circle(x, y + 3, 26, rgb(0x000000, 90));
        g.circle(x, y, 26, p == 1 ? rgb(0xFAFAFA) : rgb(0x212121));
        g.ring(x, y, 18, 2, p == 1 ? rgb(0xBDBDBD) : rgb(0x555555));
        if (game_.mustRemove && std::find(hints.begin(), hints.end(), i) != hints.end()) {
          g.ring(x, y, 28, 4, rgb(0xE53935));
        }
      }
      if (i == selected_) g.ring(x, y, 32, 5, rgb(0x7CB342));
    }
    if (!computerTurn() && !game_.isOver()) {
      auto [x, y] = pointPos(cursor_);
      g.ring(x, y, 37, 4, theme::focus);
    }
    // Stones still to place.
    for (int p = 1; p <= 2; p++) {
      const int x = p == 1 ? 120 : Gfx::W - 120;
      g.text(p == 1 ? "Weiß" : "Schwarz", x, 110, 24, theme::muted, Align::Center);
      for (int i = 0; i < game_.toPlace[p]; i++) {
        g.circle(x, 150 + i * 52, 22, p == 1 ? rgb(0xFAFAFA) : rgb(0x212121));
        g.ring(x, 150 + i * 52, 22, 2, rgb(0x777777));
      }
    }
    g.text(status(), 48, Gfx::H - 44, 26, theme::text);
    if (game_.isOver()) {
      g.hints({{"A", "Neue Partie"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", game_.mustRemove ? "Wegnehmen" : selected_ >= 0 ? "Ziehen" : "Wählen"},
               {"B", selected_ >= 0 ? "Abbrechen" : "Zurück"}});
    }
  }

 private:
  static void thick(Gfx& g, int x1, int y1, int x2, int y2, Color c) {
    if (y1 == y2) {
      g.rect(std::min(x1, x2), y1 - 3, std::abs(x2 - x1), 6, c);
    } else {
      g.rect(x1 - 3, std::min(y1, y2), 6, std::abs(y2 - y1), c);
    }
  }

  bool computerTurn() const { return vsComputer_ && game_.turn == 2 && !game_.isOver(); }

  std::string count(int p) const {
    return std::to_string(game_.stones(p) + game_.toPlace[p]);
  }

  std::vector<int> highlights() const {
    std::vector<int> out;
    if (computerTurn() || game_.isOver()) return out;
    if (game_.mustRemove) return game_.removable();
    if (game_.placing(game_.turn)) {
      for (int i = 0; i < 24; i++) {
        if (game_.board[i] == 0) out.push_back(i);
      }
      return out;
    }
    if (selected_ >= 0) return game_.targets(selected_);
    for (int i = 0; i < 24; i++) {
      if (!game_.targets(i).empty()) out.push_back(i);
    }
    return out;
  }

  std::string status() const {
    const bool white = game_.turn == 1;
    if (game_.draw) return "Unentschieden";
    if (game_.winner) {
      if (vsComputer_) return game_.winner == 1 ? "Du hast gewonnen!" : "Der Computer gewinnt";
      return game_.winner == 1 ? "Weiß gewinnt!" : "Schwarz gewinnt!";
    }
    if (computerTurn()) return "Computer überlegt …";
    std::string who = vsComputer_ ? "Du" : white ? "Weiß" : "Schwarz";
    if (game_.mustRemove) return who + ": Mühle! Nimm einen Stein weg";
    if (game_.placing(game_.turn)) return who + ": Stein setzen";
    if (game_.canFly(game_.turn)) return who + ": Springen erlaubt";
    return who + ": Stein ziehen";
  }

  void choose(int i) {
    if (game_.mustRemove) {
      game_.remove(i);
      return;
    }
    if (game_.placing(game_.turn)) {
      game_.place(i);
      return;
    }
    if (game_.board[i] == game_.turn) {
      selected_ = game_.targets(i).empty() ? -1 : i;
      return;
    }
    if (selected_ >= 0 && game_.move(selected_, i)) selected_ = -1;
  }

  // Moves the cursor to the nearest point in a direction.
  void step(int dx, int dy) {
    auto [cx, cy] = pointPos(cursor_);
    int best = -1;
    double bestScore = 1e9;
    for (int i = 0; i < 24; i++) {
      if (i == cursor_) continue;
      auto [x, y] = pointPos(i);
      const int along = (x - cx) * dx + (y - cy) * dy;
      const int across = std::abs((x - cx) * dy) + std::abs((y - cy) * dx);
      if (along <= 0) continue;
      const double score = along + across * 2.5;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (best >= 0) cursor_ = best;
  }

  void restart() {
    game_ = Mill();
    selected_ = -1;
  }

  bool vsComputer_;
  Mill game_;
  std::mt19937 rng_;
  int cursor_ = 0;
  int selected_ = -1;
  double thinking_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeMill(bool vsComputer) {
  return std::make_unique<MillScene>(vsComputer);
}
