#include <algorithm>
#include <ctime>
#include <optional>
#include <tuple>
#include <string>

#include "logic2.hpp"
#include "scene.hpp"

namespace {

constexpr int CardW = 110, CardH = 150, Gap = 24;
constexpr int Left = (Gfx::W - (7 * CardW + 6 * Gap)) / 2;
constexpr int TopY = 96, TableauY = 266, Bottom = Gfx::H - 64;

int colX(int col) { return Left + col * (CardW + Gap); }

const char* rankLabel(int r) {
  static const char* l[] = {"", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "B", "D", "K"};
  return l[r];
}
const char* suitSymbol(int s) {
  static const char* sy[] = {"♠", "♥", "♦", "♣"};
  return sy[s];
}

class SolitaireScene : public Scene {
 public:
  explicit SolitaireScene(int drawCount)
      : drawCount_(drawCount), game_(drawCount, uint32_t(std::time(nullptr))) {
    focus_ = {Area::Tableau, 0};
    clampFocus();
  }

  void update(const Input& in, double dt) override {
    if (in[BtnPlus]) {
      done = true;
      return;
    }
    if (game_.won()) {
      if (in[BtnA]) restart();
      if (in[BtnB]) done = true;
      return;
    }
    if (autoPlaying_ || game_.canAutoComplete()) {
      autoPlaying_ = true;
      autoTimer_ += dt;
      if (autoTimer_ > 0.12) {
        autoTimer_ = 0;
        if (!game_.autoStep()) autoPlaying_ = false;
      }
      return;
    }
    if (in[BtnLeft]) moveFocus(-1);
    if (in[BtnRight]) moveFocus(1);
    if (in[BtnUp]) vertical(-1);
    if (in[BtnDown]) vertical(1);
    if (in[BtnL]) {
      game_.undo();
      held_.reset();
      clampFocus();
    }
    if (in[BtnR]) {
      game_.draw();
      held_.reset();
    }
    if (in[BtnX]) smartMove(focus_);
    if (in[BtnA]) activate();
    if (in[BtnB]) {
      if (held_) {
        held_.reset();
      } else {
        done = true;
      }
    }
    if (in.tapped) tap(in.tapX, in.tapY);
  }

  void draw(Gfx& g) override {
    g.header("Solitär", "Punkte " + std::to_string(game_.score) + "   Züge " +
                            std::to_string(game_.moves));
    // Stock and waste.
    if (game_.stock.empty()) {
      slot(g, colX(0), TopY, "↺");
    } else {
      back(g, colX(0), TopY);
    }
    if (game_.waste.empty()) {
      slot(g, colX(1), TopY, "");
    } else {
      const int n = std::min<int>(drawCount_, int(game_.waste.size()));
      for (int i = 0; i < n; i++) {
        const Card& c = game_.waste[game_.waste.size() - n + i];
        face(g, colX(1) + i * 22, TopY, c, isHeld(PileRef{PileKind::Waste, 0},
                                                 int(game_.waste.size()) - n + i));
      }
    }
    for (int f = 0; f < 4; f++) {
      const auto& p = game_.foundations[f];
      if (p.empty()) {
        slot(g, colX(3 + f), TopY, "A");
      } else {
        face(g, colX(3 + f), TopY, p.back(), isHeld({PileKind::Foundation, f}, int(p.size()) - 1));
      }
    }
    // Tableau.
    for (int t = 0; t < 7; t++) {
      const auto& p = game_.tableau[t];
      if (p.empty()) slot(g, colX(t), TableauY, "K");
      for (int i = 0; i < (int)p.size(); i++) {
        const int y = cardY(t, i);
        if (p[i].faceUp) {
          face(g, colX(t), y, p[i], isHeld({PileKind::Tableau, t}, i));
        } else {
          back(g, colX(t), y);
        }
      }
    }
    // Focus frame.
    auto [fx, fy, fh] = focusRect();
    for (int i = 0; i < 4; i++) {
      g.rect(fx - 4 + i, fy - 4 + i, CardW + 8 - 2 * i, 1, theme::focus);
      g.rect(fx - 4 + i, fy + fh + 3 - i, CardW + 8 - 2 * i, 1, theme::focus);
      g.rect(fx - 4 + i, fy - 4 + i, 1, fh + 8 - 2 * i, theme::focus);
      g.rect(fx + CardW + 3 - i, fy - 4 + i, 1, fh + 8 - 2 * i, theme::focus);
    }
    if (game_.won()) {
      g.rect(0, 0, Gfx::W, Gfx::H, rgb(0x000000, 120));
      g.text("Gewonnen!", Gfx::W / 2, 280, 64, theme::focus, Align::Center);
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
      return;
    }
    g.text(held_ ? "Ziel wählen" : "", 48, Gfx::H - 44, 26, theme::text);
    g.hints({{"A", held_ ? "Ablegen" : "Nehmen"}, {"X", "Automatisch"}, {"R", "Ziehen"},
             {"L", "Rückgängig"}, {"B", held_ ? "Loslassen" : "Zurück"}});
  }

 private:
  enum class Area { Top, Tableau };
  struct Focus {
    Area area;
    int col;        // 0..6
    int depth = 0;  // tableau: card index
  };
  struct Held {
    PileRef pile;
    int index;
  };

  // --- drawing
  void slot(Gfx& g, int x, int y, const char* label) {
    g.roundRect(x, y, CardW, CardH, 10, rgb(0x1B5E20));
    g.roundRect(x + 3, y + 3, CardW - 6, CardH - 6, 8, rgb(0x2E7D32));
    if (*label) g.symbol(label, x + CardW / 2, y + CardH / 2, 40, rgb(0x66BB6A));
  }

  void back(Gfx& g, int x, int y) {
    g.roundRect(x, y, CardW, CardH, 10, rgb(0xFFFFFF));
    g.roundRect(x + 5, y + 5, CardW - 10, CardH - 10, 7, rgb(0x283593));
    g.roundRect(x + 14, y + 14, CardW - 28, CardH - 28, 5, rgb(0x3949AB));
  }

  void face(Gfx& g, int x, int y, const Card& c, bool held) {
    if (held) g.roundRect(x - 5, y - 5, CardW + 10, CardH + 10, 13, rgb(0x7CB342));
    g.roundRect(x, y, CardW, CardH, 10, rgb(0xFAFAFA));
    const Color ink = c.red() ? rgb(0xC62828) : rgb(0x212121);
    g.text(rankLabel(c.rank), x + 10, y + 4, 28, ink);
    g.symbol(suitSymbol(c.suit), x + CardW - 22, y + 22, 26, ink);
    g.symbol(suitSymbol(c.suit), x + CardW / 2, y + CardH / 2 + 18, 56, ink);
  }

  // --- layout
  int faceUpOffset(int t) const {
    const auto& p = game_.tableau[t];
    int down = 0;
    for (auto& c : p) down += !c.faceUp;
    const int up = int(p.size()) - down;
    const int room = Bottom - TableauY - CardH - down * 14;
    if (up <= 1) return 34;
    return std::max(16, std::min(34, room / (up - 1)));
  }

  int cardY(int t, int i) const {
    const auto& p = game_.tableau[t];
    int y = TableauY;
    const int up = faceUpOffset(t);
    for (int k = 0; k < i; k++) y += p[k].faceUp ? up : 14;
    return y;
  }

  std::tuple<int, int, int> focusRect() const {
    if (focus_.area == Area::Top) return {colX(focus_.col), TopY, CardH};
    const auto& p = game_.tableau[focus_.col];
    if (p.empty()) return {colX(focus_.col), TableauY, CardH};
    const int y = cardY(focus_.col, focus_.depth);
    const int bottom = cardY(focus_.col, int(p.size()) - 1) + CardH;
    return {colX(focus_.col), y, bottom - y};
  }

  // --- focus handling
  std::optional<PileRef> focusPile() const {
    if (focus_.area == Area::Tableau) return PileRef{PileKind::Tableau, focus_.col};
    if (focus_.col == 0) return PileRef{PileKind::Stock, 0};
    if (focus_.col == 1) return PileRef{PileKind::Waste, 0};
    if (focus_.col >= 3) return PileRef{PileKind::Foundation, focus_.col - 3};
    return std::nullopt;
  }

  int firstFaceUp(int t) const {
    const auto& p = game_.tableau[t];
    for (int i = 0; i < (int)p.size(); i++) {
      if (p[i].faceUp) return i;
    }
    return std::max(0, int(p.size()) - 1);
  }

  void clampFocus() {
    if (focus_.area == Area::Top) {
      if (focus_.col == 2) focus_.col = 3;
      return;
    }
    const auto& p = game_.tableau[focus_.col];
    const int last = std::max(0, int(p.size()) - 1);
    focus_.depth = std::clamp(focus_.depth, firstFaceUp(focus_.col), last);
  }

  void moveFocus(int d) {
    focus_.col = std::clamp(focus_.col + d, 0, 6);
    if (focus_.area == Area::Top && focus_.col == 2) focus_.col += d > 0 ? 1 : -1;
    if (focus_.area == Area::Tableau) focus_.depth = int(game_.tableau[focus_.col].size()) - 1;
    clampFocus();
  }

  void vertical(int d) {
    if (focus_.area == Area::Top) {
      if (d > 0) {
        focus_.area = Area::Tableau;
        focus_.depth = int(game_.tableau[focus_.col].size()) - 1;
        clampFocus();
      }
      return;
    }
    // Up: take more cards of the column; above the first open card → top row.
    if (d < 0) {
      if (focus_.depth <= firstFaceUp(focus_.col)) {
        focus_.area = Area::Top;
        clampFocus();
      } else {
        focus_.depth--;
      }
    } else {
      focus_.depth++;
      clampFocus();
    }
  }

  bool isHeld(PileRef p, int index) const {
    return held_ && held_->pile == p && index >= held_->index;
  }

  // --- actions
  void activate() {
    auto pile = focusPile();
    if (!pile) return;
    if (pile->kind == PileKind::Stock) {
      game_.draw();
      held_.reset();
      return;
    }
    if (held_) {
      if (game_.move(held_->pile, held_->index, *pile)) {
        held_.reset();
        clampFocus();
        return;
      }
    }
    const auto& cards = game_.pile(*pile);
    if (cards.empty()) {
      held_.reset();
      return;
    }
    const int index = pile->kind == PileKind::Tableau ? focus_.depth : int(cards.size()) - 1;
    if (cards[index].faceUp) held_ = Held{*pile, index};
  }

  void smartMove(const Focus& f) {
    Focus saved = focus_;
    focus_ = f;
    auto pile = focusPile();
    focus_ = saved;
    if (!pile || pile->kind == PileKind::Stock) {
      game_.draw();
      return;
    }
    const auto& cards = game_.pile(*pile);
    if (cards.empty()) return;
    const int index = pile->kind == PileKind::Tableau ? f.depth : int(cards.size()) - 1;
    if (auto to = game_.bestTarget(*pile, index)) {
      game_.move(*pile, index, *to);
      held_.reset();
      clampFocus();
    }
  }

  void tap(int x, int y) {
    for (int col = 0; col < 7; col++) {
      if (x < colX(col) || x >= colX(col) + CardW) continue;
      if (y >= TopY && y < TopY + CardH && col != 2) {
        focus_ = {Area::Top, col};
        smartMove(focus_);
        return;
      }
      const auto& p = game_.tableau[col];
      for (int i = int(p.size()) - 1; i >= 0; i--) {
        if (p[i].faceUp && y >= cardY(col, i)) {
          focus_ = {Area::Tableau, col, i};
          smartMove(focus_);
          return;
        }
      }
    }
  }

  void restart() {
    game_ = Klondike(drawCount_, uint32_t(std::time(nullptr)));
    held_.reset();
    focus_ = {Area::Tableau, 0};
    clampFocus();
  }

  int drawCount_;
  Klondike game_;
  Focus focus_;
  std::optional<Held> held_;
  bool autoPlaying_ = false;
  double autoTimer_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeSolitaire(int drawCount) {
  return std::make_unique<SolitaireScene>(drawCount);
}
