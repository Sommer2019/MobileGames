#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#include "logic3.hpp"
#include "save.hpp"
#include "scene.hpp"
#include "secrets.hpp"

namespace {

// The portrait board (1.0 × 1.6) is shown lying on its side: screen x =
// board y, screen y = board x.
constexpr double S = 560;
constexpr int Left = int((Gfx::W - BoardH * S) / 2), Top = 92;

int sx(double by) { return Left + int(by * S); }
int sy(double bx) { return Top + int(bx * S); }

std::string timeText(double t) {
  char buf[16];
  std::snprintf(buf, sizeof buf, "%.1f s", t);
  return buf;
}

class LabyrinthScene : public Scene {
 public:
  LabyrinthScene()
      : unlocked_(secrets::on(Secret::LabyrinthEasy)
                      ? labyrinthLevelCount() - 1
                      : std::clamp(Save::get().getInt("labyrinth.unlocked", 0), 0,
                                   labyrinthLevelCount() - 1)),
        level_(std::clamp(Save::get().getInt("labyrinth.unlocked", 0), 0, labyrinthLevelCount() - 1)),
        game_(labyrinthLevel(level_)) {
    applySecrets();
  }

  void update(const Input& in, double dt) override {
    if (in[BtnPlus] || in[BtnB]) {
      done = true;
      return;
    }
    if (in[BtnL] && level_ > 0) load(level_ - 1);
    if (in[BtnR] && level_ < unlocked_) load(level_ + 1);
    motionAvailable_ = in.hasMotion;
    if (in[BtnY] && in.hasMotion) {
      motion_ = !motion_;
      calibrated_ = false;
    }
    if (game_.state == BallState::Won) {
      if (in[BtnA]) load(std::min(level_ + 1, labyrinthLevelCount() - 1));
      if (in[BtnX]) game_.reset();
      return;
    }
    if (game_.state == BallState::Fell) {
      if (in[BtnA]) game_.reset();
      return;
    }
    if (in[BtnX]) {
      game_.reset();
      return;
    }
    double tiltScreenX = in.stickX, tiltScreenY = in.stickY;
    if (motion_ && in.hasMotion) {
      // Experimental: the tilt of the controller relative to when the
      // motion control was switched on.
      if (!calibrated_) {
        zeroX_ = in.accelX;
        zeroY_ = in.accelY;
        calibrated_ = true;
      }
      tiltScreenX = std::clamp((in.accelX - zeroX_) / 4.0, -1.0, 1.0);
      tiltScreenY = std::clamp(-(in.accelY - zeroY_) / 4.0, -1.0, 1.0);
    }
    if (in.touching) {
      // Touch: the ball rolls towards the finger.
      const double dx = in.touchX - sx(game_.y), dy = in.touchY - sy(game_.x);
      const double len = std::max(1.0, std::hypot(dx, dy));
      const double strength = std::min(1.0, len / 150);
      tiltScreenX = dx / len * strength;
      tiltScreenY = dy / len * strength;
    }
    if (secrets::on(Secret::Nightmare)) {
      // Albtraum: everything mirrored.
      tiltScreenX = -tiltScreenX;
      tiltScreenY = -tiltScreenY;
    }
    game_.step(dt, tiltScreenY, tiltScreenX);
    if (game_.state == BallState::Won) {
      const std::string key = "labyrinth.best." + std::to_string(level_);
      const int ms = int(game_.elapsed * 1000);
      const int best = Save::get().getInt(key);
      if (!best || ms < best) Save::get().set(key, ms);
      if (level_ == unlocked_ && unlocked_ < labyrinthLevelCount() - 1) {
        unlocked_++;
        Save::get().set("labyrinth.unlocked", unlocked_);
      }
    }
  }

  void draw(Gfx& g) override {
    const LLevel& l = game_.level;
    g.header("Labyrinth " + std::to_string(level_ + 1) + ": " + l.name, timeText(game_.elapsed));
    const int w = int(BoardH * S), h = int(BoardW * S);
    if (l.frame) g.rect(Left - 8, Top - 8, w + 16, h + 16, rgb(0x5D4037));
    g.rect(Left, Top, w, h, rgb(0xD7B98E));
    for (auto& hole : l.holes) {
      g.circle(sx(hole.y), sy(hole.x), int(hole.radius * S), rgb(0x1B1B1B));
    }
    g.circle(sx(l.goal.y), sy(l.goal.x), int(l.goal.radius * S) + 5, rgb(0x43A047));
    g.circle(sx(l.goal.y), sy(l.goal.x), int(l.goal.radius * S), rgb(0x1B5E20));
    for (auto& wall : l.walls) {
      g.rect(sx(wall.top), sy(wall.left), std::max(2, int((wall.bottom - wall.top) * S)),
             std::max(2, int((wall.right - wall.left) * S)), rgb(0x6D4C41));
    }
    if (game_.state != BallState::Fell) {
      const int bx = sx(game_.y), by = sy(game_.x), r = int(Labyrinth::Radius * S);
      g.circle(bx + 2, by + 3, r, rgb(0x000000, 80));
      g.circle(bx, by, r, rgb(0xB0BEC5));
      g.circle(bx - r / 3, by - r / 3, r / 3, rgb(0xFFFFFF));
    }
    const std::string key = "labyrinth.best." + std::to_string(level_);
    const int best = Save::get().getInt(key);
    std::string status;
    if (game_.state == BallState::Won) {
      status = "Geschafft in " + timeText(game_.elapsed) + (best ? " – Bestzeit " + timeText(best / 1000.0) : "");
    } else if (game_.state == BallState::Fell) {
      status = "Reingefallen!";
    } else {
      status = motion_ ? "Joy-Con neigen" : "Neigen mit dem Stick oder Finger";
      if (best) status += "   Bestzeit " + timeText(best / 1000.0);
    }
    g.text(status, 48, Gfx::H - 44, 24, theme::text);
    if (game_.state == BallState::Won) {
      g.hints({{"A", "Nächstes Level"}, {"X", "Nochmal"}, {"B", "Zurück"}});
    } else if (game_.state == BallState::Fell) {
      g.hints({{"A", "Nochmal"}, {"B", "Zurück"}});
    } else if (motionAvailable_) {
      g.hints({{"Y", motion_ ? "Stick" : "Bewegung"}, {"L", "Level −"}, {"R", "Level +"},
               {"X", "Neustart"}, {"B", "Zurück"}});
    } else {
      g.hints({{"L", "Level −"}, {"R", "Level +"}, {"X", "Neustart"}, {"B", "Zurück"}});
    }
  }

 private:
  void load(int i) {
    level_ = i;
    game_ = Labyrinth(labyrinthLevel(i));
    applySecrets();
  }

  void applySecrets() {
    if (secrets::on(Secret::RubberBall)) game_.restitution = 0.9;
    if (secrets::on(Secret::Nightmare)) game_.damping = 0.25;
  }

  int unlocked_, level_;
  Labyrinth game_;
  bool motion_ = false, calibrated_ = false, motionAvailable_ = false;
  double zeroX_ = 0, zeroY_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeLabyrinth() { return std::make_unique<LabyrinthScene>(); }
