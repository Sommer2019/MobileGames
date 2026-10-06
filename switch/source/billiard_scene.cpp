#include <algorithm>
#include <cmath>
#include <optional>
#include <string>

#include "logic3.hpp"
#include "save.hpp"
#include "scene.hpp"
#include "secrets.hpp"

namespace {

constexpr double Pi = 3.14159265358979323846;
constexpr double S = 470;  // pixels per table unit
constexpr int Left = int((Gfx::W - Billiard::W * S) / 2), Top = 108;

int tx(double x) { return Left + int(x * S); }
int ty(double y) { return Top + int(y * S); }

Color ballColor(int n) {
  static const uint32_t c[] = {0xFFFFFF, 0xFDD835, 0x1E88E5, 0xE53935, 0x7B1FA2, 0xFB8C00,
                               0x2E7D32, 0x8D2A2A, 0x111111};
  return rgb(c[n > 8 ? n - 8 : n]);
}

// 0 = 8 zum Schluss, 1 = Reihenfolge, 2 = 8-Ball zu zweit.
class BilliardScene : public Scene {
 public:
  explicit BilliardScene(int mode)
      : mode_(mode), solo_(mode == 1 ? SoloMode::Rotation : SoloMode::EightLast) {}

  void update(const Input& in, double dt) override {
    time_ += dt;
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (over()) {
      if (in[BtnA]) restart();
      if (in[BtnB]) done = true;
      return;
    }
    if (game_.moving()) {
      game_.step(dt);
      if (!game_.moving()) finishShot();
      return;
    }
    if (in[BtnB]) {
      done = true;
      return;
    }
    if (placing_) {
      // Cue ball in hand: move it, A puts it down.
      double nx = game_.cue().x + in.stickX * 0.6 * dt, ny = game_.cue().y + in.stickY * 0.6 * dt;
      game_.placeCue(nx, ny);
      if (in[BtnA] || in[BtnX]) placing_ = false;
      return;
    }
    if (in[BtnX] && game_.cueInHand) {
      placing_ = true;
      return;
    }
    // Aim: stick turns fast, L/R turn slowly for fine adjustment.
    angle_ += in.stickX * 1.6 * dt;
    if (in.held[BtnL]) angle_ -= 0.12 * dt;
    if (in.held[BtnR]) angle_ += 0.12 * dt;
    if (in[BtnY]) spin_ = spin_ == 0 ? 1 : spin_ == 1 ? -1 : 0;
    if (in.touching) {
      angle_ = std::atan2((in.touchY - Top) / S - game_.cue().y, (in.touchX - Left) / S - game_.cue().x);
    }
    // Hold A to charge, release to shoot.
    if (in.held[BtnA]) {
      charging_ = true;
      chargeTime_ += dt;
    } else if (charging_) {
      charging_ = false;
      shoot(power());
      chargeTime_ = 0;
    }
  }

  void draw(Gfx& g) override {
    g.header(mode_ == 2 ? "Billard – 8-Ball" : mode_ == 1 ? "Billard – Reihenfolge 1–15" : "Billard – 8 zum Schluss",
             headerRight());
    const int w = int(Billiard::W * S), h = int(Billiard::H * S);
    g.roundRect(Left - 22, Top - 22, w + 44, h + 44, 16, rgb(0x5D4037));
    g.rect(Left, Top, w, h, rgb(0x1B7A43));
    for (auto& p : Billiard::Pockets) {
      g.circle(tx(p[0]), ty(p[1]), int(Billiard::PocketRadius * S * 0.8), rgb(0x0B0B0B));
    }
    // Aim line and ghost ball.
    if (!game_.moving() && !over() && !game_.cue().pocketed && !placing_) {
      const auto p = game_.preview(angle_);
      const auto& c = game_.cue();
      g.line(tx(c.x), ty(c.y), tx(p.x), ty(p.y), 2, rgb(0xFFFFFF, 140));
      g.ring(tx(p.x), ty(p.y), int(Billiard::Radius * S), 2, rgb(0xFFFFFF, 180));
      if (p.ball >= 0) {
        const auto& b = game_.balls[size_t(p.ball)];
        g.line(tx(b.x), ty(b.y), tx(b.x + p.dirX * 0.25), ty(b.y + p.dirY * 0.25), 2,
               rgb(0xFFEB3B, 180));
      }
      // Cue stick behind the ball, pulled back while charging.
      const double back = 0.05 + power() * 0.15;
      const double sx1 = c.x - std::cos(angle_) * (back + Billiard::Radius);
      const double sy1 = c.y - std::sin(angle_) * (back + Billiard::Radius);
      const double sx2 = sx1 - std::cos(angle_) * 0.7, sy2 = sy1 - std::sin(angle_) * 0.7;
      g.line(tx(sx1), ty(sy1), tx(sx2), ty(sy2), 7, rgb(0xC8A165));
    }
    for (auto& b : game_.balls) {
      if (!b.pocketed) drawBall(g, b);
    }
    // Power meter.
    if (!game_.moving() && !over() && !placing_) {
      g.roundRect(Left, Top + h + 36, 300, 18, 9, theme::surface);
      g.roundRect(Left, Top + h + 36, int(300 * power()), 18, 9, rgb(0xFF7043));
      g.text(spin_ == 0 ? "Kein Effet" : spin_ > 0 ? "Effet: Nachläufer" : "Effet: Rückläufer",
             Left + 320, Top + h + 30, 22, theme::muted);
    }
    g.text(status(), Left + 560, Top + h + 30, 22, theme::text);
    if (!game_.moving() && !over() && !placing_) {
      g.text("Stick: zielen  ·  L/R: fein", Left, Top + h + 60, 18, theme::muted);
    }
    if (over()) {
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
    } else if (placing_) {
      g.hints({{"A", "Weiße hinlegen"}});
    } else if (game_.cueInHand) {
      g.hints({{"A", "Halten: Stoß"}, {"X", "Weiße setzen"}, {"Y", "Effet"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Halten: Stoß"}, {"Y", "Effet"}, {"B", "Zurück"}});
    }
  }

 private:
  double power() const {
    // Rises and falls while A is held.
    const double t = std::fmod(chargeTime_, 2.0);
    return charging_ || chargeTime_ > 0 ? (t < 1 ? t : 2 - t) : 0;
  }

  bool over() const {
    if (mode_ == 2) return eight_.winner >= 0;
    return solo_.lost || game_.won();
  }

  std::string headerRight() const {
    if (mode_ == 2) {
      auto label = [&](int p) {
        const Group gr = eight_.groups[p];
        return std::string("Spieler ") + std::to_string(p + 1) +
               (gr == Group::None ? "" : gr == Group::Solids ? " (Volle)" : " (Halbe)");
      };
      return label(0) + "  ·  " + label(1);
    }
    return "Stöße " + std::to_string(game_.shots + game_.fouls + solo_.penalties) +
           (best() ? "   Rekord " + std::to_string(best()) : "");
  }

  int best() const { return Save::get().getInt(mode_ == 1 ? "billiard.best.rotation" : "billiard.best.eight"); }

  std::string status() const {
    if (mode_ == 2) {
      if (eight_.winner >= 0) return eight_.lastEvent + " Spieler " + std::to_string(eight_.winner + 1) + " gewinnt.";
      const std::string who = "Spieler " + std::to_string(eight_.current + 1) + " ist dran";
      return eight_.lastEvent.empty() ? who : eight_.lastEvent + " – " + who;
    }
    if (solo_.lost) return solo_.lastEvent;
    if (game_.won()) return "Alle versenkt mit " + std::to_string(game_.shots + game_.fouls + solo_.penalties) + " Stößen!";
    const int target = solo_.target(game_);
    std::string s = solo_.lastEvent;
    if (target > 0) s += (s.empty() ? "" : " – ") + std::string("Ziel: ") + std::to_string(target);
    return s;
  }

  // Disco: a colour that changes while the ball rolls.
  static Color hue(double h) {
    h = std::fmod(h, 1.0) * 6;
    const double f = h - std::floor(h);
    const uint8_t q = uint8_t(255 * (1 - f)), t = uint8_t(255 * f);
    switch (int(h)) {
      case 0: return {255, t, 0};
      case 1: return {q, 255, 0};
      case 2: return {0, 255, t};
      case 3: return {0, q, 255};
      case 4: return {t, 0, 255};
      default: return {255, 0, q};
    }
  }

  void drawBall(Gfx& g, const PoolBall& b) {
    const int x = tx(b.x), y = ty(b.y), r = int(Billiard::Radius * S);
    g.circle(x + 2, y + 3, r, rgb(0x000000, 80));
    Color c = ballColor(b.number);
    if (secrets::on(Secret::Disco) && b.number > 0 && b.moving()) {
      c = hue(time_ * 0.8 + b.number * 0.13);
    }
    if (secrets::on(Secret::Retro)) {
      // Pixel billiard: square balls, number as a dot pattern-free label.
      g.rect(x - r, y - r, 2 * r, 2 * r, c);
      if (b.number >= 9) g.rect(x - r, y - r, 2 * r, r / 2, rgb(0xFAFAFA));
      if (b.number >= 9) g.rect(x - r, y + r / 2, 2 * r, r / 2, rgb(0xFAFAFA));
      return;
    }
    if (b.number >= 9) {
      // Stripe: white ball with a coloured band.
      for (int dy = -r; dy <= r; dy++) {
        const int dx = int(std::sqrt(double(r * r - dy * dy)));
        g.rect(x - dx, y + dy, 2 * dx + 1, 1, std::abs(dy) < r * 0.55 ? c : rgb(0xFAFAFA));
      }
    } else {
      g.circle(x, y, r, c);
    }
    if (b.number > 0) {
      g.circle(x, y, r / 2 + 2, rgb(0xFAFAFA));
      g.text(std::to_string(b.number), x, y - 7, 11, rgb(0x111111), Align::Center);
    } else {
      g.circle(x - r / 3, y - r / 3, r / 4, rgb(0xFFFFFF));
    }
  }

  void shoot(double p) {
    if (p < 0.03) return;
    othersBefore_ = SoloRules::othersLeft(game_);
    targetBefore_ = solo_.target(game_);
    clearedBefore_ = mode_ == 2 && eight_.remainingOf(game_, eight_.current) == 0 &&
                     eight_.groups[eight_.current] != Group::None;
    game_.shoot(angle_, p, spin_ * 0.8);
  }

  void finishShot() {
    if (mode_ == 2) {
      eight_.evaluate(game_.pocketedThisShot, game_.firstHit, game_.scratched, clearedBefore_);
    } else {
      solo_.evaluate(game_.pocketedThisShot, game_.firstHit, game_.scratched, othersBefore_,
                     targetBefore_);
      if (game_.won() && !solo_.lost) {
        const int score = game_.shots + game_.fouls + solo_.penalties;
        const std::string key = mode_ == 1 ? "billiard.best.rotation" : "billiard.best.eight";
        if (!best() || score < best()) Save::get().set(key, score);
      }
    }
  }

  void restart() {
    game_ = Billiard();
    eight_ = EightBall();
    solo_ = SoloRules(mode_ == 1 ? SoloMode::Rotation : SoloMode::EightLast);
    angle_ = 0;
  }

  int mode_;
  Billiard game_;
  EightBall eight_;
  SoloRules solo_;
  double angle_ = 0, chargeTime_ = 0, time_ = 0;
  int spin_ = 0;
  bool charging_ = false, placing_ = false;
  int othersBefore_ = 0, targetBefore_ = -1;
  bool clearedBefore_ = false;
};

}  // namespace

std::unique_ptr<Scene> makeBilliard(int mode) { return std::make_unique<BilliardScene>(mode); }
