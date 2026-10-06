#include <algorithm>
#include <ctime>
#include <random>
#include <string>

#include "logic.hpp"
#include "scene.hpp"
#include "secrets.hpp"

namespace {

constexpr int Sq = 68;
constexpr int Left = (Gfx::W - 8 * Sq) / 2, Top = 92;

class CheckersScene : public Scene {
 public:
  explicit CheckersScene(bool vsComputer)
      : vsComputer_(vsComputer), rng_(uint32_t(std::time(nullptr))) {
    moves_ = game_.legalMoves();
  }

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
        game_.apply(secrets::on(Secret::Grandmaster) ? game_.strongMove(rng_)
                                                     : game_.aiMove(rng_));
        moves_ = game_.legalMoves();
      }
      return;
    }
    if (in[BtnUp]) cursor_.first = std::max(0, cursor_.first - 1);
    if (in[BtnDown]) cursor_.first = std::min(7, cursor_.first + 1);
    if (in[BtnLeft]) cursor_.second = std::max(0, cursor_.second - 1);
    if (in[BtnRight]) cursor_.second = std::min(7, cursor_.second + 1);
    if (in.tapped) {
      const int r = (in.tapY - Top) / Sq, c = (in.tapX - Left) / Sq;
      if (in.tapY >= Top && in.tapX >= Left && r < 8 && c < 8) {
        cursor_ = {r, c};
        choose(cursor_);
      }
      return;
    }
    if (in[BtnA]) choose(cursor_);
    if (in[BtnB]) {
      if (path_.empty()) {
        done = true;
      } else {
        path_.clear();
      }
    }
  }

  void draw(Gfx& g) override {
    const int white = count(Side::White), black = count(Side::Black);
    g.header("Dame", "Weiß " + std::to_string(white) + "  ·  Schwarz " +
                         std::to_string(black));
    const auto targets = nextSquares();
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        const int x = Left + c * Sq, y = Top + r * Sq;
        const bool dark = (r + c) % 2 == 1;
        Color sq = dark ? rgb(0x8D6E63) : rgb(0xEFE0C8);
        if (std::find(game_.lastPath.begin(), game_.lastPath.end(), Cell{r, c}) !=
            game_.lastPath.end()) {
          sq = rgb(0xA1887F);
        }
        if (!path_.empty() && path_.front() == Cell{r, c}) sq = rgb(0x689F38);
        g.rect(x, y, Sq, Sq, sq);
        if (std::find(targets.begin(), targets.end(), Cell{r, c}) != targets.end()) {
          g.circle(x + Sq / 2, y + Sq / 2, 12, rgb(0xC5E1A5));
        }
        drawPiece(g, r, c);
      }
    }
    if (!computerTurn() && !game_.isOver()) {
      auto [r, c] = cursor_;
      for (int i = 0; i < 4; i++) {
        g.rect(Left + c * Sq + i, Top + r * Sq + i, Sq - 2 * i, 1, theme::focus);
        g.rect(Left + c * Sq + i, Top + r * Sq + Sq - 1 - i, Sq - 2 * i, 1, theme::focus);
        g.rect(Left + c * Sq + i, Top + r * Sq + i, 1, Sq - 2 * i, theme::focus);
        g.rect(Left + c * Sq + Sq - 1 - i, Top + r * Sq + i, 1, Sq - 2 * i, theme::focus);
      }
    }

    std::string status;
    const bool white_ = game_.turn == Side::White;
    if (game_.draw) {
      status = "Unentschieden";
    } else if (game_.hasWinner) {
      const bool whiteWon = game_.winner == Side::White;
      status = vsComputer_ ? (whiteWon ? "Du hast gewonnen!" : "Der Computer gewinnt")
                           : (whiteWon ? "Weiß gewinnt!" : "Schwarz gewinnt!");
    } else if (computerTurn()) {
      status = "Computer überlegt …";
    } else {
      status = vsComputer_ ? "Du bist dran" : (white_ ? "Weiß ist dran" : "Schwarz ist dran");
      if (!moves_.empty() && !moves_.front().captured.empty()) status += " – Schlagpflicht!";
    }
    g.text(status, 48, Gfx::H - 44, 26, theme::text);
    if (game_.isOver()) {
      g.hints({{"A", "Neue Partie"}, {"B", "Zurück"}});
    } else if (path_.empty()) {
      g.hints({{"A", "Stein wählen"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Ziehen"}, {"B", "Abbrechen"}});
    }
  }

 private:
  bool computerTurn() const {
    return vsComputer_ && game_.turn == Side::Black && !game_.isOver();
  }

  int count(Side s) const {
    int n = 0;
    for (auto& row : game_.board) {
      for (auto& p : row) n += p.present && p.side == s;
    }
    return n;
  }

  void drawPiece(Gfx& g, int r, int c) {
    const Piece& p = game_.board[r][c];
    if (!p.present) return;
    const int cx = Left + c * Sq + Sq / 2, cy = Top + r * Sq + Sq / 2;
    const bool w = p.side == Side::White;
    g.circle(cx, cy + 3, Sq / 2 - 7, rgb(0x000000, 90));
    g.circle(cx, cy, Sq / 2 - 7, w ? rgb(0xFAFAFA) : rgb(0x212121));
    g.ring(cx, cy, Sq / 2 - 15, 2, w ? rgb(0xBDBDBD) : rgb(0x555555));
    if (p.king) g.circle(cx, cy, 12, rgb(0xFFC107));
  }

  // Moves that start with the squares chosen so far.
  std::vector<const CheckersMove*> matching() const {
    std::vector<const CheckersMove*> out;
    for (const auto& m : moves_) {
      if (m.path.size() > path_.size() &&
          std::equal(path_.begin(), path_.end(), m.path.begin())) {
        out.push_back(&m);
      }
    }
    return out;
  }

  // Squares that can be chosen next (pieces first, then landing squares).
  std::vector<Cell> nextSquares() const {
    std::vector<Cell> out;
    if (computerTurn() || game_.isOver()) return out;
    for (const auto* m : matching()) out.push_back(m->path[path_.size()]);
    return out;
  }

  void choose(Cell sq) {
    // Pick another own piece instead.
    if (!path_.empty() && game_.board[sq.first][sq.second].present &&
        game_.board[sq.first][sq.second].side == game_.turn && sq != path_.front()) {
      path_.clear();
    }
    auto options = nextSquares();
    if (std::find(options.begin(), options.end(), sq) == options.end()) return;
    path_.push_back(sq);
    if (path_.size() < 2) return;
    // A complete move? Then play it, otherwise wait for the next landing.
    for (const auto& m : moves_) {
      if (m.path == path_) {
        bool longer = false;
        for (const auto& o : moves_) {
          longer |= o.path.size() > path_.size() &&
                    std::equal(path_.begin(), path_.end(), o.path.begin());
        }
        if (!longer) {
          game_.apply(m);
          moves_ = game_.legalMoves();
          path_.clear();
        }
        return;
      }
    }
  }

  void restart() {
    game_ = Checkers();
    moves_ = game_.legalMoves();
    path_.clear();
    cursor_ = {5, 0};
  }

  bool vsComputer_;
  Checkers game_;
  std::vector<CheckersMove> moves_;
  std::vector<Cell> path_;
  Cell cursor_{5, 0};
  std::mt19937 rng_;
  double thinking_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeCheckers(bool vsComputer) {
  return std::make_unique<CheckersScene>(vsComputer);
}
