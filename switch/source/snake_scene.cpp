#include <ctime>
#include <string>

#include "logic.hpp"
#include "save.hpp"
#include "scene.hpp"

namespace {

constexpr int Cols = 30, Rows = 14, CellSize = 40;
constexpr int Left = (Gfx::W - Cols * CellSize) / 2, Top = 96;

class SnakeScene : public Scene {
 public:
  explicit SnakeScene(bool wrap)
      : wrap_(wrap),
        key_(wrap ? "snake.best.wrap" : "snake.best"),
        game_(Cols, Rows, wrap, uint32_t(std::time(nullptr))),
        best_(Save::get().getInt(key_)) {}

  void update(const Input& in, double dt) override {
    if (game_.dead || game_.won()) {
      if (in[BtnA]) restart();
      if (in[BtnB]) done = true;
      return;
    }
    if (in[BtnPlus] || (paused_ && in[BtnA])) paused_ = !paused_;
    if (paused_) {
      if (in[BtnB]) done = true;
      return;
    }
    if (in[BtnUp] || in.swipeY < 0) game_.turn(Dir::Up);
    if (in[BtnDown] || in.swipeY > 0) game_.turn(Dir::Down);
    if (in[BtnLeft] || in.swipeX < 0) game_.turn(Dir::Left);
    if (in[BtnRight] || in.swipeX > 0) game_.turn(Dir::Right);
    if (in[BtnB]) paused_ = true;
    acc_ += dt;
    const double interval = 1.0 / game_.speed();
    while (acc_ >= interval && !game_.dead) {
      acc_ -= interval;
      game_.step();
    }
    if (game_.score > best_) {
      best_ = game_.score;
      Save::get().set(key_, best_);
    }
  }

  void draw(Gfx& g) override {
    g.header(wrap_ ? "Snake – ohne Wände" : "Snake",
             "Punkte " + std::to_string(game_.score) + "   Rekord " +
                 std::to_string(best_));
    g.rect(Left - 4, Top - 4, Cols * CellSize + 8, Rows * CellSize + 8,
           wrap_ ? rgb(0x33691E) : rgb(0x9CCC65));
    g.rect(Left, Top, Cols * CellSize, Rows * CellSize, rgb(0x1B2A1B));
    auto [fx, fy] = game_.food;
    g.circle(Left + fx * CellSize + CellSize / 2, Top + fy * CellSize + CellSize / 2,
             CellSize / 2 - 6, rgb(0xEF5350));
    for (size_t i = 0; i < game_.body.size(); i++) {
      auto [x, y] = game_.body[i];
      const Color c = i == 0 ? rgb(0xC5E1A5) : rgb(0x7CB342);
      g.roundRect(Left + x * CellSize + 2, Top + y * CellSize + 2, CellSize - 4,
                  CellSize - 4, 8, c);
    }
    if (game_.dead || game_.won()) {
      overlay(g, game_.won() ? "Geschafft!" : "Game over",
              "Punkte: " + std::to_string(game_.score));
      g.hints({{"A", "Nochmal"}, {"B", "Zurück"}});
    } else if (paused_) {
      overlay(g, "Pause", "");
      g.hints({{"A", "Weiter"}, {"B", "Beenden"}});
    } else {
      g.hints({{"+", "Pause"}});
      g.text("Steuern mit Steuerkreuz, Stick oder Wischen", 48, Gfx::H - 42, 22,
             theme::muted);
    }
  }

 private:
  void overlay(Gfx& g, const std::string& title, const std::string& sub) {
    g.rect(Left, Top, Cols * CellSize, Rows * CellSize, rgb(0x000000, 150));
    g.text(title, Gfx::W / 2, Top + 200, 64, theme::text, Align::Center);
    g.text(sub, Gfx::W / 2, Top + 290, 30, theme::muted, Align::Center);
  }

  void restart() {
    game_ = Snake(Cols, Rows, wrap_, uint32_t(std::time(nullptr)));
    acc_ = 0;
    paused_ = false;
  }

  bool wrap_;
  std::string key_;
  Snake game_;
  int best_;
  double acc_ = 0;
  bool paused_ = false;
};

}  // namespace

std::unique_ptr<Scene> makeSnake(bool wrap) {
  return std::make_unique<SnakeScene>(wrap);
}
