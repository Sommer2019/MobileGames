#include <algorithm>
#include <cmath>
#include <ctime>
#include <random>
#include <string>

#include "logic3.hpp"
#include "save.hpp"
#include "scene.hpp"

namespace {

class MahjongScene : public Scene {
 public:
  explicit MahjongScene(bool tower)
      : tower_(tower),
        game_(tower ? mahjongTower() : mahjongPyramid(), uint32_t(std::time(nullptr))),
        rng_(uint32_t(std::time(nullptr)) + 3),
        bestKey_(tower ? "mahjong.best.tower" : "mahjong.best.pyramid") {
    int maxX = 0, maxY = 0;
    for (auto& s : game_.slots) {
      maxX = std::max(maxX, s.x);
      maxY = std::max(maxY, s.y);
    }
    // Units: a tile is 2 × 2 units, a little taller than wide.
    unitW_ = std::min(1000.0 / (maxX + 2), 520.0 / ((maxY + 2) * 1.3));
    unitH_ = unitW_ * 1.3;
    left_ = int((Gfx::W - (maxX + 2) * unitW_) / 2) + 12;
    top_ = 112;
    cursor_ = firstFree();
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
    elapsed_ += dt;
    hintTime_ = std::max(0.0, hintTime_ - dt);
    if (in[BtnUp]) step(0, -1);
    if (in[BtnDown]) step(0, 1);
    if (in[BtnLeft]) step(-1, 0);
    if (in[BtnRight]) step(1, 0);
    if (in[BtnX]) {
      hint_ = game_.hint();
      hintTime_ = 2.0;
    }
    if (in[BtnL] && game_.undo()) selected_ = -1;
    if (in[BtnY] && game_.stuck()) game_.shuffleRemaining(rng_);
    if (in.tapped) {
      // Topmost tile under the finger.
      for (int i : drawOrder(true)) {
        auto [x, y, w, h] = tileRect(i);
        if (in.tapX >= x && in.tapX < x + w && in.tapY >= y && in.tapY < y + h) {
          if (game_.isFree(i)) {
            cursor_ = i;
            choose(i);
          }
          break;
        }
      }
    }
    if (in[BtnA] && cursor_ >= 0) choose(cursor_);
    if (in[BtnB]) {
      if (selected_ >= 0) {
        selected_ = -1;
      } else {
        done = true;
      }
    }
    if (cursor_ < 0 || !game_.isFree(cursor_)) cursor_ = nearestFree(cursor_);
  }

  void draw(Gfx& g) override {
    const int secs = int(elapsed_);
    g.header(tower_ ? "Mahjong – Turm" : "Mahjong – Pyramide",
             std::to_string(game_.remaining()) + " Steine   " + std::to_string(secs / 60) + ":" +
                 (secs % 60 < 10 ? "0" : "") + std::to_string(secs % 60));
    for (int i : drawOrder(false)) drawTile(g, i);
    if (game_.won()) {
      g.rect(0, 0, Gfx::W, Gfx::H, rgb(0x000000, 130));
      g.text("Geschafft!", Gfx::W / 2, 260, 64, theme::focus, Align::Center);
      const int best = Save::get().getInt(bestKey_);
      g.text("Zeit " + std::to_string(secs / 60) + ":" + (secs % 60 < 10 ? "0" : "") +
                 std::to_string(secs % 60) + (best ? "   Bestzeit " + std::to_string(best / 60) + ":" +
                                                         (best % 60 < 10 ? "0" : "") + std::to_string(best % 60)
                                                   : ""),
             Gfx::W / 2, 350, 28, theme::text, Align::Center);
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
      return;
    }
    if (game_.stuck()) {
      g.text("Keine Paare mehr – Y mischt neu", 48, Gfx::H - 44, 24, theme::focus);
      g.hints({{"Y", "Mischen"}, {"L", "Rückgängig"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", selected_ >= 0 ? "Paar wählen" : "Wählen"}, {"X", "Tipp"},
               {"L", "Rückgängig"}, {"B", selected_ >= 0 ? "Abbrechen" : "Zurück"}});
    }
  }

 private:
  std::tuple<int, int, int, int> tileRect(int i) const {
    const MjSlot& s = game_.slots[size_t(i)];
    const int x = left_ + int(s.x * unitW_) - s.z * 5;
    const int y = top_ + int(s.y * unitH_) - s.z * 6;
    return {x, y, int(2 * unitW_) - 2, int(2 * unitH_) - 2};
  }

  // Bottom layer first; [topFirst] reverses it (for hit tests).
  std::vector<int> drawOrder(bool topFirst) const {
    std::vector<int> order;
    for (size_t i = 0; i < game_.slots.size(); i++) {
      if (!game_.removed[i]) order.push_back(int(i));
    }
    std::sort(order.begin(), order.end(), [&](int a, int b) {
      const auto &sa = game_.slots[size_t(a)], &sb = game_.slots[size_t(b)];
      if (sa.z != sb.z) return sa.z < sb.z;
      if (sa.y != sb.y) return sa.y < sb.y;
      return sa.x < sb.x;
    });
    if (topFirst) std::reverse(order.begin(), order.end());
    return order;
  }

  void drawTile(Gfx& g, int i) {
    auto [x, y, w, h] = tileRect(i);
    const bool free = game_.isFree(i);
    const bool hinted = hintTime_ > 0 && hint_ && (hint_->first == i || hint_->second == i);
    // Side (depth) and face.
    g.roundRect(x + 5, y + 6, w, h, 8, rgb(0x8D6E63));
    g.roundRect(x + 2, y + 3, w, h, 8, rgb(0xD7CCC8));
    Color face = free ? rgb(0xFFF8E1) : rgb(0xE0D6C2);
    if (i == selected_) face = rgb(0xC5E1A5);
    if (hinted) face = rgb(0xFFE082);
    g.roundRect(x, y, w, h, 8, face);
    drawFace(g, game_.faces[size_t(i)], x, y, w, h, free);
    if (i == cursor_) {
      for (int k = 0; k < 3; k++) {
        g.rect(x - 3 + k, y - 3 + k, w + 6 - 2 * k, 1, theme::focus);
        g.rect(x - 3 + k, y + h + 2 - k, w + 6 - 2 * k, 1, theme::focus);
        g.rect(x - 3 + k, y - 3 + k, 1, h + 6 - 2 * k, theme::focus);
        g.rect(x + w + 2 - k, y - 3 + k, 1, h + 6 - 2 * k, theme::focus);
      }
    }
  }

  // Drawn faces instead of Chinese characters: red numbers, blue circles,
  // green bamboo, winds as letters, dragons as coloured symbols.
  void drawFace(Gfx& g, const MjFace& f, int x, int y, int w, int h, bool free) {
    const uint8_t a = free ? 255 : 150;
    const int cx = x + w / 2, cy = y + h / 2;
    switch (f.suit) {
      case 0:
        g.text(std::to_string(f.rank + 1), cx, y + h / 2 - int(h * 0.36), int(h * 0.5),
               rgb(0xC62828, a), Align::Center);
        g.rect(x + w / 4, y + h - h / 5, w / 2, std::max(2, h / 22), rgb(0xC62828, a));
        break;
      case 1:
      case 2: {
        const int n = f.rank + 1;
        const int cols = n <= 4 ? 2 : 3, rows = (n + cols - 1) / cols;
        const double cw = (w - 12.0) / cols, ch = (h - 12.0) / rows;
        for (int k = 0; k < n; k++) {
          const int px = x + 6 + int((k % cols + 0.5) * cw), py = y + 6 + int((k / cols + 0.5) * ch);
          if (f.suit == 1) {
            g.circle(px, py, int(std::min(cw, ch) * 0.36), rgb(0x1565C0, a));
            g.circle(px, py, int(std::min(cw, ch) * 0.14), rgb(0xFFF8E1));
          } else {
            g.roundRect(px - int(cw * 0.15), py - int(ch * 0.4), int(cw * 0.3), int(ch * 0.8), 3,
                        rgb(0x2E7D32, a));
          }
        }
        break;
      }
      case 3: {
        static const char* winds[] = {"O", "S", "W", "N"};
        g.text(winds[f.rank], cx, cy - int(h * 0.3), int(h * 0.5), rgb(0x283593, a), Align::Center);
        break;
      }
      default: {
        static const char* dragons[] = {"●", "▲", "□"};
        static const Color colors[] = {rgb(0xC62828), rgb(0x2E7D32), rgb(0x1565C0)};
        Color c = colors[f.rank];
        c.a = a;
        g.symbol(dragons[f.rank], cx, cy, int(h * 0.55), c);
      }
    }
  }

  int firstFree() const {
    for (size_t i = 0; i < game_.slots.size(); i++) {
      if (game_.isFree(int(i))) return int(i);
    }
    return -1;
  }

  std::pair<double, double> centre(int i) const {
    auto [x, y, w, h] = tileRect(i);
    return {x + w / 2.0, y + h / 2.0};
  }

  int nearestFree(int from) const {
    if (from < 0) return firstFree();
    auto [fx, fy] = centre(from);
    int best = -1;
    double bestD = 1e18;
    for (size_t i = 0; i < game_.slots.size(); i++) {
      if (!game_.isFree(int(i))) continue;
      auto [x, y] = centre(int(i));
      const double d = std::hypot(x - fx, y - fy);
      if (d < bestD) {
        bestD = d;
        best = int(i);
      }
    }
    return best;
  }

  // Next free tile in a direction.
  void step(int dx, int dy) {
    if (cursor_ < 0) return;
    auto [cx, cy] = centre(cursor_);
    int best = -1;
    double bestScore = 1e18;
    for (size_t i = 0; i < game_.slots.size(); i++) {
      if (int(i) == cursor_ || !game_.isFree(int(i))) continue;
      auto [x, y] = centre(int(i));
      const double along = (x - cx) * dx + (y - cy) * dy;
      const double across = std::abs((x - cx) * dy) + std::abs((y - cy) * dx);
      if (along <= 4) continue;
      const double score = along + across * 2;
      if (score < bestScore) {
        bestScore = score;
        best = int(i);
      }
    }
    if (best >= 0) cursor_ = best;
  }

  void choose(int i) {
    if (!game_.isFree(i)) return;
    if (selected_ < 0 || selected_ == i) {
      selected_ = selected_ == i ? -1 : i;
      return;
    }
    if (game_.match(selected_, i)) {
      selected_ = -1;
      hint_.reset();
      if (game_.won()) {
        const int best = Save::get().getInt(bestKey_);
        if (!best || int(elapsed_) < best) Save::get().set(bestKey_, int(elapsed_));
      }
    } else {
      selected_ = i;
    }
  }

  void restart() {
    game_ = Mahjong(tower_ ? mahjongTower() : mahjongPyramid(), uint32_t(std::time(nullptr)));
    selected_ = -1;
    elapsed_ = 0;
    cursor_ = firstFree();
  }

  bool tower_;
  Mahjong game_;
  std::mt19937 rng_;
  std::string bestKey_;
  double unitW_ = 30, unitH_ = 40;
  int left_ = 0, top_ = 0;
  int cursor_ = -1, selected_ = -1;
  double elapsed_ = 0, hintTime_ = 0;
  std::optional<std::pair<int, int>> hint_;
};

}  // namespace

std::unique_ptr<Scene> makeMahjong(bool tower) { return std::make_unique<MahjongScene>(tower); }
