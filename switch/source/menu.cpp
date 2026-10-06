#include <tuple>
#include <algorithm>

#include "scene.hpp"

namespace {

struct Tile {
  const char* title;
  const char* subtitle;
  Color color;
  std::function<std::unique_ptr<Scene>()> open;
};

// Shared look of the menu tiles and the choice lists.
void tileBox(Gfx& g, int x, int y, int w, int h, Color c, bool focused) {
  if (focused) g.roundRect(x - 6, y - 6, w + 12, h + 12, 26, theme::focus);
  g.roundRect(x, y, w, h, 20, c);
}

bool hit(const Input& in, int x, int y, int w, int h) {
  return in.tapped && in.tapX >= x && in.tapX < x + w && in.tapY >= y &&
         in.tapY < y + h;
}

class Menu : public Scene {
 public:
  Menu() {
    tiles_ = {
        {"Snake", "Fressen, wachsen – nicht anstoßen",
         rgb(0x558B2F),
         [] {
           return makeChoices(
               "Snake", rgb(0x558B2F),
               {{"Normal", "Die Wand ist tödlich", [] { return makeSnake(false); }},
                {"Ohne Wände", "Durch den Rand auf die andere Seite",
                 [] { return makeSnake(true); }}});
         }},
        {"4 gewinnt", "Vier in einer Reihe – 2 bis 4 Spieler", rgb(0xC62828),
         [] {
           return makeChoices(
               "4 gewinnt", rgb(0xC62828),
               {{"Gegen Computer", "Du spielst Rot",
                 [] { return makeConnectFour(2, true); }},
                {"2 Spieler", "Abwechselnd an einer Switch",
                 [] { return makeConnectFour(2, false); }},
                {"3 Spieler", "Größeres Brett, 9 × 7",
                 [] { return makeConnectFour(3, false); }},
                {"4 Spieler", "Größeres Brett, 10 × 8",
                 [] { return makeConnectFour(4, false); }}});
         }},
        {"Dame", "Schlagen ist Pflicht – mit fliegenden Damen", rgb(0x5D4037),
         [] {
           return makeChoices(
               "Dame", rgb(0x5D4037),
               {{"Gegen Computer", "Du spielst Weiß",
                 [] { return makeCheckers(true); }},
                {"2 Spieler", "Abwechselnd an einer Switch",
                 [] { return makeCheckers(false); }}});
         }},
        {"Würfelbecher", "1–6 Würfel, beiseitelegen, Verlauf",
         rgb(0x2E7D32), [] { return makeDiceCup(); }},
    };
  }

  void update(const Input& in, double) override {
    const int cols = 2;
    if (in[BtnRight] && focus_ % cols < cols - 1 && focus_ + 1 < (int)tiles_.size()) focus_++;
    if (in[BtnLeft] && focus_ % cols > 0) focus_--;
    if (in[BtnDown] && focus_ + cols < (int)tiles_.size()) focus_ += cols;
    if (in[BtnUp] && focus_ - cols >= 0) focus_ -= cols;
    for (size_t i = 0; i < tiles_.size(); i++) {
      auto [x, y, w, h] = box(int(i));
      if (hit(in, x, y, w, h)) {
        focus_ = int(i);
        push = tiles_[i].open();
        return;
      }
    }
    if (in[BtnA]) push = tiles_[focus_].open();
    if (in[BtnPlus]) done = true;  // leaves the app
  }

  void draw(Gfx& g) override {
    g.header("Mobile Games", "Offline – allein oder zusammen");
    for (size_t i = 0; i < tiles_.size(); i++) {
      auto [x, y, w, h] = box(int(i));
      const Tile& t = tiles_[i];
      tileBox(g, x, y, w, h, t.color, int(i) == focus_);
      g.text(t.title, x + 32, y + h - 112, 44, rgb(0xFFFFFF));
      g.text(t.subtitle, x + 32, y + h - 52, 22, rgb(0xFFFFFF, 210));
    }
    g.hints({{"A", "Starten"}, {"+", "Beenden"}});
  }

 private:
  std::tuple<int, int, int, int> box(int i) const {
    const int w = 560, h = 240, gap = 40;
    const int left = (Gfx::W - 2 * w - gap) / 2;
    return {left + (i % 2) * (w + gap), 120 + (i / 2) * (h + gap), w, h};
  }

  std::vector<Tile> tiles_;
  int focus_ = 0;
};

class Choices : public Scene {
 public:
  Choices(std::string title, Color color, std::vector<Choice> choices)
      : title_(std::move(title)), color_(color), choices_(std::move(choices)) {}

  void update(const Input& in, double) override {
    const int n = int(choices_.size());
    if (in[BtnDown]) focus_ = (focus_ + 1) % n;
    if (in[BtnUp]) focus_ = (focus_ + n - 1) % n;
    for (int i = 0; i < n; i++) {
      if (hit(in, left(), top(i), width(), 96)) {
        focus_ = i;
        push = choices_[i].open();
        return;
      }
    }
    if (in[BtnA]) push = choices_[focus_].open();
    if (in[BtnB]) done = true;
  }

  void draw(Gfx& g) override {
    g.header(title_);
    for (int i = 0; i < int(choices_.size()); i++) {
      const bool f = i == focus_;
      tileBox(g, left(), top(i), width(), 96, f ? color_ : theme::surface, f);
      g.text(choices_[i].label, left() + 32, top(i) + 14, 32, theme::text);
      g.text(choices_[i].detail, left() + 32, top(i) + 56, 22,
             f ? rgb(0xFFFFFF, 220) : theme::muted);
    }
    g.hints({{"A", "Spielen"}, {"B", "Zurück"}});
  }

 private:
  int width() const { return 720; }
  int left() const { return (Gfx::W - width()) / 2; }
  int top(int i) const { return 120 + i * 120; }

  std::string title_;
  Color color_;
  std::vector<Choice> choices_;
  int focus_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeMenu() { return std::make_unique<Menu>(); }

std::unique_ptr<Scene> makeChoices(std::string title, Color color,
                                   std::vector<Choice> choices) {
  return std::make_unique<Choices>(std::move(title), color, std::move(choices));
}
