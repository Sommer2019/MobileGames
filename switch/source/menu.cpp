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
    auto vs = [](const char* title, Color c, std::function<std::unique_ptr<Scene>(bool)> make) {
      return [=] {
        return makeChoices(title, c,
                           {{"Gegen Computer", "Du fängst an", [=] { return make(true); }},
                            {"2 Spieler", "Abwechselnd an einer Switch",
                             [=] { return make(false); }}});
      };
    };
    tiles_ = {
        {"Schach", "Der Klassiker mit allen Regeln", rgb(0x6D4C41),
         vs("Schach", rgb(0x6D4C41), makeChess)},
        {"Schiffe versenken", "Finde die gegnerische Flotte", rgb(0x1565C0),
         vs("Schiffe versenken", rgb(0x1565C0), makeBattleship)},
        {"4 gewinnt", "Vier in einer Reihe – 2 bis 4", rgb(0xC62828),
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
        {"Dame", "Schlagen ist Pflicht", rgb(0x4E342E),
         vs("Dame", rgb(0x4E342E), makeCheckers)},
        {"Mühle", "Drei in einer Reihe", rgb(0xE65100),
         vs("Mühle", rgb(0xE65100), makeMill)},
        {"Kniffel", "Würfelglück mit Taktik", rgb(0x2E7D32),
         [] {
           return makeChoices(
               "Kniffel", rgb(0x2E7D32),
               {{"Allein", "Auf Rekordjagd", [] { return makeKniffel(1, false); }},
                {"Gegen Computer", "Du und der Computer", [] { return makeKniffel(1, true); }},
                {"2 Spieler", "Abwechselnd", [] { return makeKniffel(2, false); }},
                {"3 Spieler", "Abwechselnd", [] { return makeKniffel(3, false); }},
                {"4 Spieler", "Abwechselnd", [] { return makeKniffel(4, false); }}});
         }},
        {"Snake", "Fressen, wachsen – nicht anstoßen", rgb(0x558B2F),
         [] {
           return makeChoices(
               "Snake", rgb(0x558B2F),
               {{"Normal", "Die Wand ist tödlich", [] { return makeSnake(false); }},
                {"Ohne Wände", "Durch den Rand auf die andere Seite",
                 [] { return makeSnake(true); }}});
         }},
        {"Solitär", "Klondike", rgb(0x00695C),
         [] {
           return makeChoices(
               "Solitär", rgb(0x00695C),
               {{"1 Karte ziehen", "Die klassische Variante", [] { return makeSolitaire(1); }},
                {"3 Karten ziehen", "Schwerer", [] { return makeSolitaire(3); }}});
         }},
        {"Würfelbecher", "1–6 Würfel, beiseitelegen", rgb(0x33691E),
         [] { return makeDiceCup(); }},
    };
  }

  void update(const Input& in, double) override {
    const int n = int(tiles_.size());
    if (in[BtnRight] && focus_ % Cols < Cols - 1 && focus_ + 1 < n) focus_++;
    if (in[BtnLeft] && focus_ % Cols > 0) focus_--;
    if (in[BtnDown] && focus_ + Cols < n) focus_ += Cols;
    if (in[BtnUp] && focus_ - Cols >= 0) focus_ -= Cols;
    // Swiping up scrolls down (the focus follows).
    if (in.swipeY) focus_ = std::clamp(focus_ - in.swipeY * Cols, 0, n - 1);
    // Keep the focused row visible.
    const int row = focus_ / Cols;
    if (row < firstRow_) firstRow_ = row;
    if (row >= firstRow_ + VisibleRows) firstRow_ = row - VisibleRows + 1;

    for (int i = 0; i < n; i++) {
      auto [x, y, w, h] = box(i);
      if (y < 90 || y + h > Gfx::H - 60) continue;
      if (hit(in, x, y, w, h)) {
        focus_ = i;
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
      if (y < 90 || y + h > Gfx::H - 60) continue;
      const Tile& t = tiles_[i];
      tileBox(g, x, y, w, h, t.color, int(i) == focus_);
      g.text(t.title, x + 24, y + h - 84, 34, rgb(0xFFFFFF));
      g.text(t.subtitle, x + 24, y + h - 40, 20, rgb(0xFFFFFF, 210));
    }
    const int rows = (int(tiles_.size()) + Cols - 1) / Cols;
    if (firstRow_ + VisibleRows < rows) g.symbol("\u25BC", Gfx::W / 2, 650, 18, theme::muted);
    g.hints({{"A", "Starten"}, {"+", "Beenden"}});
  }

 private:
  static constexpr int Cols = 3, VisibleRows = 3;

  std::tuple<int, int, int, int> box(int i) const {
    const int w = 376, h = 162, gap = 24;
    const int left = (Gfx::W - Cols * w - (Cols - 1) * gap) / 2;
    const int row = i / Cols - firstRow_;
    return {left + (i % Cols) * (w + gap), 102 + row * (h + gap), w, h};
  }

  std::vector<Tile> tiles_;
  int focus_ = 0;
  int firstRow_ = 0;
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
      if (hit(in, left(), top(i), width(), itemH())) {
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
      const int pad = (itemH() - 78) / 2;
      tileBox(g, left(), top(i), width(), itemH(), f ? color_ : theme::surface, f);
      g.text(choices_[i].label, left() + 32, top(i) + pad, 32, theme::text);
      g.text(choices_[i].detail, left() + 32, top(i) + pad + 44, 22,
             f ? rgb(0xFFFFFF, 220) : theme::muted);
    }
    g.hints({{"A", "Spielen"}, {"B", "Zurück"}});
  }

 private:
  int width() const { return 720; }
  int left() const { return (Gfx::W - width()) / 2; }
  int itemH() const { return choices_.size() > 4 ? 86 : 96; }
  int top(int i) const { return 116 + i * (itemH() + (choices_.size() > 4 ? 16 : 24)); }

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
