#include <algorithm>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <random>
#include <string>

#include "logic3.hpp"
#include "save.hpp"
#include "scene.hpp"

namespace {

constexpr double Pi = 3.14159265358979323846;
constexpr int CX = 420, CY = 372;
constexpr double Scale = 232.0 / dartboard::DoubleOuter;  // pixels per mm

const char* modeName(DartsMode m) {
  return m == DartsMode::X501 ? "501" : m == DartsMode::X301 ? "301" : "Rund um die Uhr";
}

class DartsScene : public Scene {
 public:
  DartsScene(DartsMode mode, int players)
      : mode_(mode), game_(players, mode), rng_(uint32_t(std::time(nullptr))) {}

  void update(const Input& in, double dt) override {
    time_ += dt;
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (game_.isOver()) {
      if (in[BtnA]) {
        game_ = Darts(game_.players, mode_);
        shown_.clear();
        info_.clear();
      }
      if (in[BtnB]) done = true;
      return;
    }
    if (in[BtnB]) {
      done = true;
      return;
    }
    // Aim with the stick (fast) – the hand always wobbles a little.
    aimX_ = std::clamp(aimX_ + in.stickX * 170 * dt, -230.0, 230.0);
    aimY_ = std::clamp(aimY_ + in.stickY * 170 * dt, -230.0, 230.0);
    if (in.touching) {
      aimX_ = (in.touchX - CX) / Scale;
      aimY_ = (in.touchY - CY) / Scale;
      fingerAiming_ = true;
    } else if (fingerAiming_) {
      // Lifting the finger throws.
      fingerAiming_ = false;
      throwDart();
      return;
    }
    if (in[BtnA]) throwDart();
  }

  void draw(Gfx& g) override {
    g.header(std::string("Darts – ") + modeName(mode_),
             "Runde " + std::to_string(game_.round));
    drawBoard(g);
    for (auto& [x, y] : shown_) drawDart(g, x, y);
    if (!game_.isOver()) {
      // Crosshair at the wobbling aim point.
      const auto [wx, wy] = sway();
      const int ax = CX + int((aimX_ + wx) * Scale), ay = CY + int((aimY_ + wy) * Scale);
      g.ring(ax, ay, 14, 3, rgb(0xFFFFFF));
      g.rect(ax - 22, ay - 1, 44, 3, rgb(0xFFFFFF));
      g.rect(ax - 1, ay - 22, 3, 44, rgb(0xFFFFFF));
    }
    // Scores.
    const int px = 760;
    for (int p = 0; p < game_.players; p++) {
      const auto& s = game_.states[size_t(p)];
      const int y = 110 + p * 110;
      const bool cur = p == game_.current && !game_.isOver();
      g.roundRect(px, y, 470, 96, 16, cur ? rgb(0x3949AB) : theme::surface);
      g.text(game_.players == 1 ? "Du" : "Spieler " + std::to_string(p + 1), px + 20, y + 10, 24,
             theme::muted);
      const std::string big = mode_ == DartsMode::Clock
                                  ? "Ziel " + std::to_string(game_.target(p))
                                  : std::to_string(s.remaining);
      g.text(big, px + 20, y + 38, 40, theme::text);
      char avg[32];
      std::snprintf(avg, sizeof avg, "Ø %.1f", s.average());
      g.text(std::to_string(s.darts) + " Darts", px + 450, y + 14, 22, theme::muted, Align::Right);
      if (mode_ != DartsMode::Clock) g.text(avg, px + 450, y + 52, 22, theme::muted, Align::Right);
    }
    // Darts of this turn.
    std::string turn;
    for (auto& h : game_.turn) turn += (turn.empty() ? "" : "  ") + h.label();
    g.text(turn, px, 110 + game_.players * 110 + 10, 28, theme::text);
    g.text(info_, 48, Gfx::H - 44, 26, game_.isOver() ? theme::focus : theme::text);
    if (game_.isOver()) {
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Werfen"}, {"B", "Zurück"}});
    }
  }

 private:
  std::pair<double, double> sway() const {
    return {std::sin(time_ * 1.9) * 7 + std::sin(time_ * 4.3) * 3,
            std::cos(time_ * 2.4) * 7 + std::sin(time_ * 3.1) * 3};
  }

  double gauss() {
    std::uniform_real_distribution<double> u(1e-9, 1);
    return std::sqrt(-2 * std::log(u(rng_))) * std::cos(2 * Pi * u(rng_));
  }

  void throwDart() {
    const int player = game_.current;
    const auto [wx, wy] = sway();
    const double x = aimX_ + wx + gauss() * 5, y = aimY_ + wy + gauss() * 5;
    const DartHit hit = dartboard::score(x, y);
    if (shownFor_ != player || shown_.size() >= 3) {
      shown_.clear();
      shownFor_ = player;
    }
    shown_.push_back({x, y});
    game_.throwDart(hit);
    const std::string who = game_.players == 1 ? "" : "Spieler " + std::to_string(player + 1) + ": ";
    if (game_.lastBust && game_.turn.empty()) {
      info_ = who + "überworfen!";
    } else {
      info_ = who + hit.label();
    }
    if (game_.isOver()) {
      if (game_.players == 1) {
        const std::string key = std::string("darts.best.") + modeName(mode_);
        const int best = Save::get().getInt(key);
        const int darts = game_.states[0].darts;
        if (!best || darts < best) Save::get().set(key, darts);
        info_ = "Geschafft mit " + std::to_string(darts) + " Darts" +
                (best && best < darts ? " (Rekord " + std::to_string(best) + ")" : " – Rekord!");
      } else {
        info_ = "Spieler " + std::to_string(game_.winner + 1) + " gewinnt!";
      }
    }
  }

  // One ring piece of a segment, as small convex quads.
  static void sector(Gfx& g, double a0, double a1, double r0, double r1, Color c) {
    const int steps = 4;
    for (int i = 0; i < steps; i++) {
      const double s = a0 + (a1 - a0) * i / steps, e = a0 + (a1 - a0) * (i + 1) / steps;
      const float xs[4] = {float(CX + std::sin(s) * r1), float(CX + std::sin(e) * r1),
                           float(CX + std::sin(e) * r0), float(CX + std::sin(s) * r0)};
      const float ys[4] = {float(CY - std::cos(s) * r1), float(CY - std::cos(e) * r1),
                           float(CY - std::cos(e) * r0), float(CY - std::cos(s) * r0)};
      g.polygon(xs, ys, 4, c);
    }
  }

  void drawBoard(Gfx& g) {
    using namespace dartboard;
    g.circle(CX, CY, int(207 * Scale), rgb(0x212121));
    for (int i = 0; i < 20; i++) {
      const double a0 = (i * 18 - 9) * Pi / 180, a1 = (i * 18 + 9) * Pi / 180;
      const bool dark = i % 2 == 0;
      const Color single = dark ? rgb(0x1E1E1E) : rgb(0xF3E5C0);
      const Color ring = dark ? rgb(0xD32F2F) : rgb(0x2E7D32);
      sector(g, a0, a1, DoubleInner * Scale, DoubleOuter * Scale, ring);
      sector(g, a0, a1, TripleOuter * Scale, DoubleInner * Scale, single);
      sector(g, a0, a1, TripleInner * Scale, TripleOuter * Scale, ring);
      sector(g, a0, a1, BullOuter * Scale, TripleInner * Scale, single);
      const double mid = i * 18 * Pi / 180;
      g.text(std::to_string(Numbers[i]), CX + int(std::sin(mid) * 193 * Scale),
             CY - int(std::cos(mid) * 193 * Scale) - 13, 22, rgb(0xFFFFFF), Align::Center);
    }
    g.circle(CX, CY, int(BullOuter * Scale), rgb(0x2E7D32));
    g.circle(CX, CY, int(BullInner * Scale) + 1, rgb(0xD32F2F));
  }

  static void drawDart(Gfx& g, double x, double y) {
    const int px = CX + int(x * Scale), py = CY + int(y * Scale);
    // Flight towards the bottom right, tip at the hit point.
    g.line(px, py, px + 26, py + 26, 4, rgb(0xB0BEC5));
    g.circle(px + 28, py + 28, 8, rgb(0x1E88E5));
    g.circle(px, py, 3, rgb(0x000000));
    g.circle(px, py, 1, rgb(0xFFFFFF));
  }

  DartsMode mode_;
  Darts game_;
  std::mt19937 rng_;
  double time_ = 0, aimX_ = 0, aimY_ = -103;  // T20
  bool fingerAiming_ = false;
  std::vector<std::pair<double, double>> shown_;
  int shownFor_ = -1;
  std::string info_;
};

}  // namespace

std::unique_ptr<Scene> makeDarts(int mode, int players) {
  return std::make_unique<DartsScene>(DartsMode(mode), players);
}
