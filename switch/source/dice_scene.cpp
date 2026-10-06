#include <cstdlib>
#include <algorithm>
#include <ctime>
#include <random>
#include <sstream>
#include <string>

#include "logic.hpp"
#include "save.hpp"
#include "scene.hpp"

namespace {

constexpr int DieSize = 110, Gap = 34;
constexpr int RowY = 108, HeldY = 272;

class DiceScene : public Scene {
 public:
  DiceScene() : rng_(uint32_t(std::time(nullptr))) {
    cup_.count = std::clamp(Save::get().getInt("dice.count", 2), 1, 6);
    // "3,5;1,2,6" = newest roll first.
    std::stringstream all(Save::get().getString("dice.history"));
    std::string roll;
    while (std::getline(all, roll, ';') && cup_.history.size() < 10) {
      std::vector<int> v;
      std::stringstream one(roll);
      std::string n;
      while (std::getline(one, n, ',')) v.push_back(std::atoi(n.c_str()));
      if (!v.empty()) cup_.history.push_back(v);
    }
    if (!cup_.history.empty()) {
      const auto& last = cup_.history.front();
      for (size_t i = 0; i < last.size() && i < 6; i++) cup_.values[i] = last[i];
    }
  }

  void update(const Input& in, double dt) override {
    if (in[BtnB] || in[BtnPlus]) {
      done = true;
      return;
    }
    if (rolling_ > 0) {
      rolling_ -= dt;
      flicker_ -= dt;
      if (flicker_ <= 0) {
        flicker_ = 0.06;
        std::uniform_int_distribution<int> die(1, 6);
        for (int i = 0; i < cup_.count; i++) {
          if (!cup_.held[i]) shown_[i] = die(rng_);
        }
      }
      if (rolling_ <= 0) finishRoll();
      return;
    }
    if (in[BtnLeft]) focus_ = (focus_ + cup_.count - 1) % cup_.count;
    if (in[BtnRight]) focus_ = (focus_ + 1) % cup_.count;
    if (in[BtnY]) cup_.held[focus_] = !cup_.held[focus_];
    if (in[BtnL] || in[BtnDown]) setCount(cup_.count - 1);
    if (in[BtnR] || in[BtnUp]) setCount(cup_.count + 1);
    if (in[BtnX]) {
      cup_.history.clear();
      saveHistory();
    }
    if (in.tapped) {
      for (int i = 0; i < cup_.count; i++) {
        auto [x, y] = diePos(i);
        if (in.tapX >= x && in.tapX < x + DieSize && in.tapY >= y &&
            in.tapY < y + DieSize) {
          focus_ = i;
          cup_.held[i] = !cup_.held[i];
          return;
        }
      }
      startRoll();
      return;
    }
    if (in[BtnA]) startRoll();
  }

  void draw(Gfx& g) override {
    g.header("Würfelbecher", std::to_string(cup_.count) +
                                 " Würfel");
    // Dice set aside lie in the tray below the line.
    g.roundRect(80, 244, Gfx::W - 160, 4, 2, theme::surfaceHigh);
    g.text("Beiseite", 80, 254, 20, theme::muted);
    for (int i = 0; i < cup_.count; i++) {
      auto [x, y] = diePos(i);
      const int v = rolling_ > 0 ? shown_[i] : cup_.values[i];
      if (i == focus_ && rolling_ <= 0) {
        g.roundRect(x - 7, y - 7, DieSize + 14, DieSize + 14, 26, theme::focus);
      }
      drawDie(g, x, y, v, cup_.held[i]);
    }
    const int sum = rolling_ > 0 ? 0 : cup_.sum();
    g.text(rolling_ > 0 ? "…" : "Summe " + std::to_string(sum), Gfx::W / 2, 404,
           40, theme::text, Align::Center);

    g.text("Verlauf", 80, 470, 24, theme::muted);
    int i = 0;
    for (const auto& roll : cup_.history) {
      std::string line;
      int s = 0;
      for (size_t k = 0; k < roll.size(); k++) {
        line += (k ? " " : "") + std::to_string(roll[k]);
        s += roll[k];
      }
      line += "  = " + std::to_string(s);
      const int col = i / 5, row = i % 5;
      g.text(line, 80 + col * 560, 504 + row * 30, 22,
             i == 0 ? theme::text : theme::muted);
      i++;
    }
    if (cup_.history.empty()) g.text("Noch nicht gewürfelt", 80, 504, 22, theme::muted);
    g.hints({{"A", "Würfeln"}, {"Y", "Beiseite"}, {"L", "−"}, {"R", "+"},
             {"X", "Verlauf löschen"}, {"B", "Zurück"}});
  }

 private:
  std::pair<int, int> diePos(int i) const {
    const int width = cup_.count * DieSize + (cup_.count - 1) * Gap;
    const int x = (Gfx::W - width) / 2 + i * (DieSize + Gap);
    return {x, cup_.held[i] ? HeldY : RowY};
  }

  void drawDie(Gfx& g, int x, int y, int v, bool held) {
    g.roundRect(x, y + 6, DieSize, DieSize, 22, rgb(0x000000, 90));
    g.roundRect(x, y, DieSize, DieSize, 22, held ? rgb(0xFFE082) : rgb(0xFAFAFA));
    static const int pips[7][6][2] = {
        {},
        {{1, 1}},
        {{0, 0}, {2, 2}},
        {{0, 0}, {1, 1}, {2, 2}},
        {{0, 0}, {2, 0}, {0, 2}, {2, 2}},
        {{0, 0}, {2, 0}, {1, 1}, {0, 2}, {2, 2}},
        {{0, 0}, {2, 0}, {0, 1}, {2, 1}, {0, 2}, {2, 2}},
    };
    for (int k = 0; k < v; k++) {
      const int px = x + 25 + pips[v][k][0] * 30, py = y + 25 + pips[v][k][1] * 30;
      g.circle(px, py, 10, rgb(0x212121));
    }
  }

  void setCount(int n) {
    n = std::clamp(n, 1, 6);
    if (n == cup_.count) return;
    cup_.count = n;
    cup_.held = {};
    focus_ = std::min(focus_, n - 1);
    Save::get().set("dice.count", n);
  }

  void startRoll() {
    bool any = false;
    for (int i = 0; i < cup_.count; i++) any |= !cup_.held[i];
    if (!any) return;  // everything set aside
    for (int i = 0; i < 6; i++) shown_[i] = cup_.values[i];
    rolling_ = 0.7;
    flicker_ = 0;
  }

  void finishRoll() {
    cup_.roll(rng_);
    saveHistory();
  }

  void saveHistory() {
    std::string s;
    for (const auto& roll : cup_.history) {
      if (!s.empty()) s += ';';
      for (size_t k = 0; k < roll.size(); k++) s += (k ? "," : "") + std::to_string(roll[k]);
    }
    Save::get().set("dice.history", s);
  }

  DiceCup cup_;
  std::mt19937 rng_;
  int focus_ = 0;
  double rolling_ = 0, flicker_ = 0;
  int shown_[6] = {1, 1, 1, 1, 1, 1};
};

}  // namespace

std::unique_ptr<Scene> makeDiceCup() { return std::make_unique<DiceScene>(); }
