#include <algorithm>
#include <cctype>
#include <ctime>
#include <random>
#include <string>

#include "logic2.hpp"
#include "scene.hpp"

namespace {

constexpr int Sq = 68;
constexpr int Left = (Gfx::W - 8 * Sq) / 2, Top = 92;

// Solid and outline glyphs (♚♛♜♝♞♟ / ♔♕♖♗♘♙).
std::string glyph(char piece, bool solid) {
  static const char* solidG[] = {"♚", "♛", "♜", "♝", "♞", "♟"};
  static const char* outlineG[] = {"♔", "♕", "♖", "♗", "♘", "♙"};
  const std::string order = "KQRBNP";
  const auto i = order.find(char(std::toupper(piece)));
  if (i == std::string::npos) return "";
  return solid ? solidG[i] : outlineG[i];
}

class ChessScene : public Scene {
 public:
  explicit ChessScene(bool vsComputer)
      : vsComputer_(vsComputer), rng_(uint32_t(std::time(nullptr))) {}

  void update(const Input& in, double dt) override {
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (over_) {
      if (in[BtnA]) restart();
      if (in[BtnB]) done = true;
      return;
    }
    if (promoting_) {
      if (in[BtnLeft]) promoChoice_ = (promoChoice_ + 3) % 4;
      if (in[BtnRight]) promoChoice_ = (promoChoice_ + 1) % 4;
      if (in[BtnB]) promoting_ = false;
      if (in[BtnA]) {
        promoting_ = false;
        play({selected_, promoTo_, "qrbn"[promoChoice_]});
      }
      return;
    }
    if (computerTurn()) {
      thinking_ += dt;
      if (thinking_ > 0.5) {
        thinking_ = 0;
        play(game_.aiMove(rng_));
      }
      return;
    }
    // Rank 7 is on top; the cursor moves in screen directions.
    if (in[BtnUp]) cursor_ = std::min(63, cursor_ + 8 * (cursor_ / 8 < 7));
    if (in[BtnDown]) cursor_ = std::max(0, cursor_ - 8 * (cursor_ / 8 > 0));
    if (in[BtnLeft] && cursor_ % 8 > 0) cursor_--;
    if (in[BtnRight] && cursor_ % 8 < 7) cursor_++;
    if (in.tapped && in.tapX >= Left && in.tapX < Left + 8 * Sq && in.tapY >= Top &&
        in.tapY < Top + 8 * Sq) {
      const int f = (in.tapX - Left) / Sq, r = 7 - (in.tapY - Top) / Sq;
      cursor_ = r * 8 + f;
      choose(cursor_);
      return;
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
    g.header("Schach", vsComputer_ ? "Du spielst Weiß" : "Zwei Spieler");
    std::vector<int> targets;
    if (selected_ >= 0) {
      for (auto& m : game_.movesFrom(selected_)) targets.push_back(m.to);
    }
    const int king = kingInCheck();
    for (int r = 7; r >= 0; r--) {
      for (int f = 0; f < 8; f++) {
        const int sq = r * 8 + f;
        const int x = Left + f * Sq, y = Top + (7 - r) * Sq;
        Color c = (r + f) % 2 ? rgb(0xF0D9B5) : rgb(0xB58863);
        if (sq == game_.lastFrom || sq == game_.lastTo) c = (r + f) % 2 ? rgb(0xF6EB72) : rgb(0xDCC34B);
        if (sq == selected_) c = rgb(0x8BC34A);
        if (sq == king) c = rgb(0xE57373);
        g.rect(x, y, Sq, Sq, c);
        if (std::find(targets.begin(), targets.end(), sq) != targets.end()) {
          if (game_.board[sq]) {
            g.ring(x + Sq / 2, y + Sq / 2, Sq / 2 - 2, 5, rgb(0x33691E, 160));
          } else {
            g.circle(x + Sq / 2, y + Sq / 2, 11, rgb(0x33691E, 150));
          }
        }
        drawPiece(g, game_.board[sq], x + Sq / 2, y + Sq / 2);
      }
    }
    // Coordinates.
    for (int i = 0; i < 8; i++) {
      g.text(std::string(1, char('a' + i)), Left + i * Sq + Sq / 2, Top + 8 * Sq + 2, 18,
             theme::muted, Align::Center);
      g.text(std::to_string(8 - i), Left - 18, Top + i * Sq + Sq / 2 - 11, 18, theme::muted,
             Align::Center);
    }
    if (!computerTurn() && !over_) {
      const int x = Left + cursor_ % 8 * Sq, y = Top + (7 - cursor_ / 8) * Sq;
      for (int i = 0; i < 4; i++) {
        g.rect(x + i, y + i, Sq - 2 * i, 1, theme::focus);
        g.rect(x + i, y + Sq - 1 - i, Sq - 2 * i, 1, theme::focus);
        g.rect(x + i, y + i, 1, Sq - 2 * i, theme::focus);
        g.rect(x + Sq - 1 - i, y + i, 1, Sq - 2 * i, theme::focus);
      }
    }
    if (promoting_) {
      g.rect(0, 0, Gfx::W, Gfx::H, rgb(0x000000, 140));
      g.roundRect(Gfx::W / 2 - 220, 250, 440, 200, 20, theme::surface);
      g.text("Umwandeln in", Gfx::W / 2, 268, 26, theme::text, Align::Center);
      for (int i = 0; i < 4; i++) {
        const int cx = Gfx::W / 2 - 150 + i * 100;
        if (i == promoChoice_) g.roundRect(cx - 42, 316, 84, 100, 14, theme::focus);
        g.roundRect(cx - 38, 320, 76, 92, 12, rgb(0xF0D9B5));
        drawPiece(g, game_.whiteToMove ? "QRBN"[i] : "qrbn"[i], cx, 366);
      }
    }
    g.text(status(), 48, Gfx::H - 44, 26, theme::text);
    if (over_) {
      g.hints({{"A", "Neue Partie"}, {"B", "Zurück"}});
    } else if (promoting_) {
      g.hints({{"A", "Wählen"}, {"B", "Abbrechen"}});
    } else {
      g.hints({{"A", selected_ >= 0 ? "Ziehen" : "Figur wählen"},
               {"B", selected_ >= 0 ? "Abbrechen" : "Zurück"}});
    }
  }

 private:
  static void drawPiece(Gfx& g, char p, int cx, int cy) {
    if (!p) return;
    const bool white = p >= 'A' && p <= 'Z';
    g.symbol(glyph(p, true), cx, cy + 2, 56, white ? rgb(0xFFFFFF) : rgb(0x1E1E1E));
    g.symbol(glyph(p, false), cx, cy + 2, 56, white ? rgb(0x1E1E1E) : rgb(0x1E1E1E));
  }

  bool computerTurn() const { return vsComputer_ && !game_.whiteToMove && !over_; }

  int kingInCheck() const {
    if (!game_.inCheck()) return -1;
    for (int i = 0; i < 64; i++) {
      if (game_.board[i] == (game_.whiteToMove ? 'K' : 'k')) return i;
    }
    return -1;
  }

  std::string status() const {
    if (game_.checkmate()) {
      const bool whiteWon = !game_.whiteToMove;
      if (vsComputer_) return whiteWon ? "Schachmatt – du gewinnst!" : "Schachmatt – der Computer gewinnt";
      return whiteWon ? "Schachmatt – Weiß gewinnt" : "Schachmatt – Schwarz gewinnt";
    }
    if (game_.stalemate()) return "Patt – Remis";
    if (game_.draw()) return "Remis";
    if (computerTurn()) return "Computer überlegt …";
    const std::string who = vsComputer_ ? "" : game_.whiteToMove ? "Weiß" : "Schwarz";
    if (game_.inCheck()) return vsComputer_ ? "Du stehst im Schach!" : who + " steht im Schach!";
    return vsComputer_ ? "Du bist am Zug" : who + " ist am Zug";
  }

  void choose(int sq) {
    const char p = game_.board[sq];
    const bool own = p && game_.isWhite(sq) == game_.whiteToMove;
    if (own) {
      selected_ = game_.movesFrom(sq).empty() ? -1 : sq;
      return;
    }
    if (selected_ < 0) return;
    for (auto& m : game_.movesFrom(selected_)) {
      if (m.to != sq) continue;
      if (game_.isPromotion(selected_, sq)) {
        promoting_ = true;
        promoTo_ = sq;
        promoChoice_ = 0;
        return;
      }
      play({selected_, sq, 0});
      return;
    }
  }

  void play(ChessMove m) {
    game_.play(m);
    selected_ = -1;
    over_ = game_.isOver();
  }

  void restart() {
    game_ = Chess();
    selected_ = -1;
    over_ = false;
    cursor_ = 12;
  }

  bool vsComputer_;
  Chess game_;
  std::mt19937 rng_;
  int cursor_ = 12;  // e2
  int selected_ = -1;
  bool over_ = false;
  bool promoting_ = false;
  int promoTo_ = -1, promoChoice_ = 0;
  double thinking_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeChess(bool vsComputer) {
  return std::make_unique<ChessScene>(vsComputer);
}
