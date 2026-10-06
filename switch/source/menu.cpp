#include <tuple>
#include <algorithm>
#include <cstdlib>

#include "scene.hpp"
#include "secrets.hpp"

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
        {"Vier in einer Reihe", "Steine in eine Reihe bringen – 2 bis 4", rgb(0xC62828),
         [] {
           return makeChoices(
               "Vier in einer Reihe", rgb(0xC62828),
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
        {"Würfelkönig", "Würfelglück mit Taktik", rgb(0x2E7D32),
         [] {
           return makeChoices(
               "Würfelkönig", rgb(0x2E7D32),
               {{"Allein", "Auf Rekordjagd", [] { return makeKniffel(1, false); }},
                {"Gegen Computer", "Du und der Computer", [] { return makeKniffel(1, true); }},
                {"2 Spieler", "Abwechselnd", [] { return makeKniffel(2, false); }},
                {"3 Spieler", "Abwechselnd", [] { return makeKniffel(3, false); }},
                {"4 Spieler", "Abwechselnd", [] { return makeKniffel(4, false); }}});
         }},
        {"Darts", "501, 301 oder Rund um die Uhr", rgb(0xB71C1C),
         [] {
           auto players = [](int mode, const char* title) {
             return [=] {
               std::vector<Choice> c;
               for (int p = 1; p <= 4; p++) {
                 c.push_back({p == 1 ? "Allein" : std::to_string(p) + " Spieler",
                              p == 1 ? "Rekord in möglichst wenigen Darts" : "Abwechselnd werfen",
                              [=] { return makeDarts(mode, p); }});
               }
               return makeChoices(title, rgb(0xB71C1C), c);
             };
           };
           return makeChoices(
               "Darts", rgb(0xB71C1C),
               {{"501", "Double out", players(0, "Darts – 501")},
                {"301", "Double out", players(1, "Darts – 301")},
                {"Rund um die Uhr", "1 bis 20, dann Bull", players(2, "Darts – Rund um die Uhr")}});
         }},
        {"Billard", "Allein oder 8-Ball zu zweit", rgb(0x1B5E20),
         [] {
           return makeChoices(
               "Billard", rgb(0x1B5E20),
               {{"8 zum Schluss", "Allein: alle versenken, die 8 zuletzt",
                 [] { return makeBilliard(0); }},
                {"Reihenfolge 1–15", "Allein: immer die niedrigste zuerst",
                 [] { return makeBilliard(1); }},
                {"8-Ball zu zweit", "Volle gegen Halbe", [] { return makeBilliard(2); }}});
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
        {"Kugellabyrinth", "26 Level – kipp die Kugel ins Ziel", rgb(0x795548),
         [] { return makeLabyrinth(); }},
        {"Mahjong", "Gleiche freie Steine abräumen", rgb(0x00838F),
         [] {
           return makeChoices(
               "Mahjong", rgb(0x00838F),
               {{"Pyramide", "120 Steine, breit", [] { return makeMahjong(false); }},
                {"Turm", "108 Steine, hoch", [] { return makeMahjong(true); }}});
         }},
        {"Würfelbecher", "1–6 Würfel, beiseitelegen", rgb(0x33691E),
         [] { return makeDiceCup(); }},
    };
    if (secrets::unlocked()) addSecretTile();
  }

  void update(const Input& in, double dt) override {
    celebrate_ = std::max(0.0, celebrate_ - dt);
    for (auto& c : confetti_) {
      c.y += c.vy * dt;
      c.x += c.vx * dt;
    }
    // Konami code: ↑↑↓↓←→←→ B A + (A and + do not act while it is typed).
    if (konami(in)) return;
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
    if (celebrate_ > 0) {
      for (auto& c : confetti_) g.rect(int(c.x), int(c.y), 10, 6, c.color);
      g.roundRect(240, 300, 800, 120, 24, rgb(0x000000, 200));
      g.text("Geheimcode! Geheimnisse freigeschaltet", Gfx::W / 2, 320, 32, theme::focus,
             Align::Center);
      g.text("Neue Kachel: Geheimmenü", Gfx::W / 2, 368, 24, theme::text, Align::Center);
    }
    g.hints({{"A", "Starten"}, {"+", "Beenden"}});
  }

 private:
  struct Bit {
    float x, y, vx, vy;
    Color color;
  };

  // Returns true when the input belongs to the code and was used up.
  bool konami(const Input& in) {
    static const Button code[] = {BtnUp,    BtnUp,   BtnDown,  BtnDown, BtnLeft, BtnRight,
                                  BtnLeft,  BtnRight, BtnB,    BtnA,    BtnPlus};
    constexpr int len = int(sizeof code / sizeof code[0]);
    int pressed = -1;
    for (int b = 0; b < BtnCount; b++) {
      if (in.fresh[b]) pressed = b;
    }
    if (pressed < 0) return false;
    if (pressed == code[konami_]) {
      konami_++;
      if (konami_ == len) {
        konami_ = 0;
        secrets::unlock();
        addSecretTile();
        celebrate_ = 3.5;
        confetti_.clear();
        for (int i = 0; i < 160; i++) {
          confetti_.push_back({float(std::rand() % Gfx::W), float(-(std::rand() % 400)),
                               float(std::rand() % 80 - 40), float(160 + std::rand() % 240),
                               rgb(uint32_t(std::rand()) & 0xFFFFFF)});
        }
        return true;
      }
      // B, A and + are part of the code here, not menu actions.
      return pressed == BtnA || pressed == BtnPlus || pressed == BtnB;
    }
    konami_ = pressed == code[0] ? 1 : 0;
    return false;
  }

  void addSecretTile() {
    for (auto& t : tiles_) {
      if (std::string(t.title) == "Geheimmenü") return;
    }
    tiles_.push_back({"Geheimmenü", "Die Extras aus dem Geheimcode", rgb(0x6A1B9A),
                      [] { return makeSecrets(); }});
  }

  int konami_ = 0;
  double celebrate_ = 0;
  std::vector<Bit> confetti_;

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

class SecretsScene : public Scene {
 public:
  void update(const Input& in, double) override {
    const int n = int(Secret::Count);
    if (in[BtnDown]) focus_ = (focus_ + 1) % n;
    if (in[BtnUp]) focus_ = (focus_ + n - 1) % n;
    for (int i = 0; i < n; i++) {
      if (hit(in, 160, top(i), 960, 66)) {
        focus_ = i;
        toggle(i);
        return;
      }
    }
    if (in[BtnA]) toggle(focus_);
    if (in[BtnB] || in[BtnPlus]) done = true;
  }

  void draw(Gfx& g) override {
    g.header("Geheimmenü", "Geheimcode");
    for (int i = 0; i < int(Secret::Count); i++) {
      const Secret s = Secret(i);
      const bool f = i == focus_, on = secrets::on(s);
      tileBox(g, 160, top(i), 960, 66, f ? rgb(0x4A148C) : theme::surface, f);
      g.text(secrets::title(s), 190, top(i) + 6, 26, theme::text);
      g.text(secrets::description(s), 190, top(i) + 38, 19, theme::muted);
      // Switch.
      g.roundRect(1040, top(i) + 20, 56, 28, 14, on ? rgb(0x7CB342) : theme::surfaceHigh);
      g.circle(on ? 1082 : 1054, top(i) + 34, 11, rgb(0xFFFFFF));
    }
    g.hints({{"A", "An/Aus"}, {"B", "Zurück"}});
  }

 private:
  static int top(int i) { return 100 + i * 78; }
  void toggle(int i) { secrets::set(Secret(i), !secrets::on(Secret(i))); }
  int focus_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeSecrets() { return std::make_unique<SecretsScene>(); }

std::unique_ptr<Scene> makeMenu() { return std::make_unique<Menu>(); }

std::unique_ptr<Scene> makeChoices(std::string title, Color color,
                                   std::vector<Choice> choices) {
  return std::make_unique<Choices>(std::move(title), color, std::move(choices));
}
