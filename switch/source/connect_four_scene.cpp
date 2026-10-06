#include <algorithm>
#include <string>

#include "logic.hpp"
#include "scene.hpp"

namespace {

const Color PlayerColors[] = {rgb(0xE53935), rgb(0xFDD835), rgb(0x43A047),
                              rgb(0x1E88E5)};
const char* PlayerNames[] = {"Rot", "Gelb", "Grün", "Blau"};

class ConnectFourScene : public Scene {
 public:
  ConnectFourScene(int players, bool vsComputer)
      : players_(players), vsComputer_(vsComputer), game_(players),
        wins_(players, 0) {
    cursor_ = game_.columns / 2;
  }

  void update(const Input& in, double dt) override {
    if (in[BtnB] || in[BtnPlus]) {
      done = true;
      return;
    }
    if (falling_) {
      fallY_ += dt * 2400;
      if (fallY_ >= targetY_) falling_ = false;
      return;
    }
    if (game_.isOver()) {
      if (in[BtnA] || in.tapped) newRound();
      return;
    }
    if (computerTurn()) {
      thinking_ += dt;
      if (thinking_ > 0.4) {
        thinking_ = 0;
        play(game_.aiMove());
      }
      return;
    }
    if (in[BtnLeft]) cursor_ = std::max(0, cursor_ - 1);
    if (in[BtnRight]) cursor_ = std::min(game_.columns - 1, cursor_ + 1);
    if (in.tapped) {
      const int col = (in.tapX - left()) / cell();
      if (col >= 0 && col < game_.columns) {
        cursor_ = col;
        play(col);
      }
      return;
    }
    if (in[BtnA] || in[BtnDown]) play(cursor_);
  }

  void draw(Gfx& g) override {
    std::string score;
    for (int p = 0; p < players_; p++) {
      if (p) score += "  ·  ";
      score += std::string(PlayerNames[p]) + " " + std::to_string(wins_[p]);
    }
    g.header("Vier in einer Reihe", score);

    const int c = cell(), l = left(), t = top();
    const int w = game_.columns * c, h = game_.rows * c;
    // Disc above the board for the player to move.
    if (!game_.isOver() && !falling_) {
      g.circle(l + cursor_ * c + c / 2, t - c / 2, c / 2 - 8,
               PlayerColors[game_.current - 1]);
    }
    g.roundRect(l - 12, t - 12, w + 24, h + 24, 18, rgb(0x1565C0));
    for (int r = 0; r < game_.rows; r++) {
      for (int col = 0; col < game_.columns; col++) {
        const int cx = l + col * c + c / 2, cy = t + r * c + c / 2;
        const int v = board(r, col);
        g.circle(cx, cy, c / 2 - 7, v ? PlayerColors[v - 1] : theme::background);
      }
    }
    if (falling_) {
      g.circle(l + fallCol_ * c + c / 2, t + int(fallY_) + c / 2, c / 2 - 7,
               PlayerColors[fallPlayer_ - 1]);
    }
    if (game_.winner && !falling_) {
      for (auto [r, col] : game_.winningCells) {
        g.ring(l + col * c + c / 2, t + r * c + c / 2, c / 2 - 7, 6,
               rgb(0xFFFFFF));
      }
    }

    std::string status;
    if (falling_) {
      status = "";
    } else if (game_.winner) {
      status = vsComputer_ ? (game_.winner == 1 ? "Du hast gewonnen!"
                                                : "Der Computer gewinnt")
                           : std::string(PlayerNames[game_.winner - 1]) +
                                 " gewinnt!";
    } else if (game_.draw) {
      status = "Unentschieden";
    } else if (computerTurn()) {
      status = "Computer überlegt …";
    } else {
      status = vsComputer_ ? "Du bist dran"
                           : std::string(PlayerNames[game_.current - 1]) +
                                 " ist dran";
    }
    g.text(status, 48, Gfx::H - 44, 26, theme::text);
    if (game_.isOver()) {
      g.hints({{"A", "Neue Runde"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Einwerfen"}, {"B", "Zurück"}});
    }
  }

 private:
  bool computerTurn() const {
    return vsComputer_ && game_.current == 2 && !game_.isOver();
  }

  // While the disc falls, its target cell still looks empty.
  int board(int r, int col) const {
    if (falling_ && r == fallRow_ && col == fallCol_) return 0;
    return game_.board[r][col];
  }

  void play(int col) {
    const int player = game_.current;
    const int row = game_.drop(col);
    if (row < 0) return;
    falling_ = true;
    fallCol_ = col;
    fallRow_ = row;
    fallPlayer_ = player;
    fallY_ = -cell();
    targetY_ = row * cell();
    if (game_.winner) wins_[game_.winner - 1]++;
  }

  void newRound() {
    game_ = ConnectFour(players_);
    // Rotate who starts.
    starter_ = starter_ % players_ + 1;
    game_.current = starter_;
    cursor_ = game_.columns / 2;
  }

  int cell() const {
    // One extra row above the board for the disc to drop.
    return std::min(540 / (game_.rows + 1), 1000 / game_.columns);
  }
  int left() const { return (Gfx::W - game_.columns * cell()) / 2; }
  int top() const { return 96 + cell(); }

  int players_;
  bool vsComputer_;
  ConnectFour game_;
  std::vector<int> wins_;
  int cursor_ = 0;
  int starter_ = 1;
  double thinking_ = 0;
  bool falling_ = false;
  int fallCol_ = 0, fallRow_ = 0, fallPlayer_ = 1;
  double fallY_ = 0, targetY_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeConnectFour(int players, bool vsComputer) {
  return std::make_unique<ConnectFourScene>(players, vsComputer);
}
