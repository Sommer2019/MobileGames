#include <ctime>
#include <random>
#include <string>

#include "logic2.hpp"
#include "scene.hpp"

namespace {

constexpr int Big = 48, Small = 36;
constexpr int ChartX = 600, ChartY = 132;
constexpr int OwnX = 64, OwnY = 168;

class BattleshipScene : public Scene {
 public:
  explicit BattleshipScene(bool vsComputer)
      : vsComputer_(vsComputer), rng_(uint32_t(std::time(nullptr))) {
    fleets_[0] = Fleet::random(rng_);
    fleets_[1] = Fleet::random(rng_);
    // Every human first checks (and maybe reshuffles) their fleet.
    phase_ = Phase::Place;
    placing_ = 0;
    cover_ = !vsComputer_;
  }

  void update(const Input& in, double dt) override {
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (cover_) {
      // Hand the console over without showing the fleet.
      if (in[BtnA] || in.tapped) cover_ = false;
      if (in[BtnB]) done = true;
      return;
    }
    switch (phase_) {
      case Phase::Place:
        if (in[BtnY]) fleets_[placing_] = Fleet::random(rng_);
        if (in[BtnA]) {
          if (!vsComputer_ && placing_ == 0) {
            placing_ = 1;
            cover_ = true;
          } else {
            phase_ = Phase::Play;
            current_ = 0;
            cover_ = !vsComputer_;
            message_ = "";
          }
        }
        if (in[BtnB]) done = true;
        return;
      case Phase::Over:
        if (in[BtnA]) restart();
        if (in[BtnB]) done = true;
        return;
      case Phase::Play:
        break;
    }
    if (waitForNext_ > 0) {
      waitForNext_ -= dt;
      if (waitForNext_ <= 0) {
        current_ = 1 - current_;
        cover_ = !vsComputer_;
      }
      return;
    }
    if (vsComputer_ && current_ == 1) {
      thinking_ += dt;
      if (thinking_ > 0.7) {
        thinking_ = 0;
        auto [x, y] = battleshipAiShot(charts_[1], rng_);
        shoot(x, y);
      }
      return;
    }
    if (in[BtnUp] && cursor_.second > 0) cursor_.second--;
    if (in[BtnDown] && cursor_.second < SeaSize - 1) cursor_.second++;
    if (in[BtnLeft] && cursor_.first > 0) cursor_.first--;
    if (in[BtnRight] && cursor_.first < SeaSize - 1) cursor_.first++;
    if (in.tapped && in.tapX >= ChartX && in.tapY >= ChartY && in.tapX < ChartX + SeaSize * Big &&
        in.tapY < ChartY + SeaSize * Big) {
      cursor_ = {(in.tapX - ChartX) / Big, (in.tapY - ChartY) / Big};
      shoot(cursor_.first, cursor_.second);
      return;
    }
    if (in[BtnA]) shoot(cursor_.first, cursor_.second);
    if (in[BtnB]) done = true;
  }

  void draw(Gfx& g) override {
    g.header("Schiffe versenken", vsComputer_ ? "Gegen Computer" : "Zwei Spieler");
    if (cover_) {
      const int who = phase_ == Phase::Place ? placing_ : current_;
      g.text("Spieler " + std::to_string(who + 1) + " ist dran", Gfx::W / 2, 260, 48,
             theme::text, Align::Center);
      g.text("Gib die Switch weiter – der andere schaut weg.", Gfx::W / 2, 340, 26,
             theme::muted, Align::Center);
      g.hints({{"A", "Los"}, {"B", "Zurück"}});
      return;
    }
    if (phase_ == Phase::Place) {
      const std::string who = vsComputer_ ? "Deine Flotte" : "Flotte von Spieler " + std::to_string(placing_ + 1);
      g.text(who, Gfx::W / 2, 100, 30, theme::text, Align::Center);
      drawFleet(g, fleets_[placing_], (Gfx::W - SeaSize * Big) / 2, 150, Big, true);
      g.hints({{"A", "Fertig"}, {"Y", "Neu verteilen"}, {"B", "Zurück"}});
      return;
    }
    const int me = vsComputer_ ? 0 : current_;
    const int opp = 1 - me;
    g.text(vsComputer_ ? "Deine Flotte" : "Flotte Spieler " + std::to_string(me + 1), OwnX, OwnY - 40,
           22, theme::muted);
    drawFleet(g, fleets_[me], OwnX, OwnY, Small, true);
    g.text(vsComputer_ ? "Gegner" : "Flotte Spieler " + std::to_string(opp + 1), ChartX, ChartY - 36,
           22, theme::muted);
    drawChart(g, charts_[me], ChartX, ChartY);
    const bool myTurn = !(vsComputer_ && current_ == 1);
    if (phase_ == Phase::Play && myTurn && waitForNext_ <= 0) {
      const int x = ChartX + cursor_.first * Big, y = ChartY + cursor_.second * Big;
      for (int i = 0; i < 4; i++) {
        g.rect(x + i, y + i, Big - 2 * i, 1, theme::focus);
        g.rect(x + i, y + Big - 1 - i, Big - 2 * i, 1, theme::focus);
        g.rect(x + i, y + i, 1, Big - 2 * i, theme::focus);
        g.rect(x + Big - 1 - i, y + i, 1, Big - 2 * i, theme::focus);
      }
    }
    std::string status = message_;
    if (status.empty()) {
      status = myTurn ? (vsComputer_ ? "Du schießt" : "Spieler " + std::to_string(current_ + 1) + " schießt")
                      : "Computer zielt …";
    }
    g.text(status, 48, Gfx::H - 44, 26, theme::text);
    if (phase_ == Phase::Over) {
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Schießen"}, {"B", "Zurück"}});
    }
  }

 private:
  enum class Phase { Place, Play, Over };

  static void drawWater(Gfx& g, int x, int y, int cell) {
    g.rect(x - 2, y - 2, SeaSize * cell + 4, SeaSize * cell + 4, rgb(0x0D47A1));
    for (int r = 0; r < SeaSize; r++) {
      for (int c = 0; c < SeaSize; c++) {
        g.rect(x + c * cell + 1, y + r * cell + 1, cell - 2, cell - 2, rgb(0x1976D2));
      }
    }
  }

  static void drawFleet(Gfx& g, const Fleet& f, int x, int y, int cell, bool showShips) {
    drawWater(g, x, y, cell);
    for (auto& s : f.ships) {
      for (auto [cx, cy] : s.cells) {
        if (showShips || s.sunk()) {
          g.roundRect(x + cx * cell + 3, y + cy * cell + 3, cell - 6, cell - 6, 6,
                      s.sunk() ? rgb(0x424242) : rgb(0x90A4AE));
        }
      }
    }
    for (auto [sx, sy] : f.shots) {
      const int cx = x + sx * cell + cell / 2, cy = y + sy * cell + cell / 2;
      if (f.shipAt(sx, sy)) {
        g.circle(cx, cy, cell / 4, rgb(0xE53935));
      } else {
        g.circle(cx, cy, cell / 8, rgb(0xBBDEFB));
      }
    }
  }

  static void drawChart(Gfx& g, const Chart& c, int x, int y) {
    drawWater(g, x, y, Big);
    for (int r = 0; r < SeaSize; r++) {
      for (int col = 0; col < SeaSize; col++) {
        const int cx = x + col * Big + Big / 2, cy = y + r * Big + Big / 2;
        switch (c.cells[r][col]) {
          case Mark::Miss: g.circle(cx, cy, 6, rgb(0xBBDEFB)); break;
          case Mark::Hit: g.circle(cx, cy, 14, rgb(0xE53935)); break;
          case Mark::Sunk:
            g.roundRect(x + col * Big + 3, y + r * Big + 3, Big - 6, Big - 6, 6, rgb(0x424242));
            g.circle(cx, cy, 10, rgb(0xE53935));
            break;
          default: break;
        }
      }
    }
  }

  void shoot(int x, int y) {
    Chart& chart = charts_[current_];
    if (!chart.canShoot(x, y)) return;
    std::vector<Cell> sunk;
    const Shot s = fleets_[1 - current_].receive(x, y, &sunk);
    chart.apply(x, y, s, sunk);
    const bool computer = vsComputer_ && current_ == 1;
    if (fleets_[1 - current_].allSunk()) {
      phase_ = Phase::Over;
      message_ = vsComputer_ ? (computer ? "Der Computer hat gewonnen" : "Gewonnen! Alle Schiffe versenkt")
                             : "Spieler " + std::to_string(current_ + 1) + " gewinnt!";
      return;
    }
    if (s == Shot::Miss) {
      message_ = computer ? "Computer: Wasser – du bist dran" : "Wasser";
      if (!vsComputer_) {
        waitForNext_ = 1.2;
      } else {
        current_ = 1 - current_;
      }
    } else {
      message_ = s == Shot::Sunk ? (computer ? "Computer: versenkt! Er schießt nochmal" : "Versenkt! Nochmal")
                                 : (computer ? "Computer: Treffer! Er schießt nochmal" : "Treffer! Nochmal");
    }
  }

  void restart() {
    fleets_[0] = Fleet::random(rng_);
    fleets_[1] = Fleet::random(rng_);
    charts_[0] = Chart();
    charts_[1] = Chart();
    phase_ = Phase::Place;
    placing_ = 0;
    current_ = 0;
    cover_ = !vsComputer_;
    message_.clear();
  }

  bool vsComputer_;
  std::mt19937 rng_;
  Fleet fleets_[2];
  Chart charts_[2];  // what player i knows about the other fleet
  Phase phase_;
  int placing_ = 0, current_ = 0;
  bool cover_ = false;
  Cell cursor_{4, 4};
  std::string message_;
  double thinking_ = 0, waitForNext_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeBattleship(bool vsComputer) {
  return std::make_unique<BattleshipScene>(vsComputer);
}
