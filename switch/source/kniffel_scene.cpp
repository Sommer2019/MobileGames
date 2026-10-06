#include <ctime>
#include <random>
#include <string>

#include "logic2.hpp"
#include "scene.hpp"

namespace {

constexpr int DieSize = 84, DieGap = 14, DiceX = 48, DiceY = 150;
constexpr int TableX = 560, TableY = 96, RowH = 31, LabelW = 210;

// Rows of the score sheet: the 13 categories plus sums.
enum Row { SumUpper = CatCount, Bonus, Total, RowCount };
int rowY(int row) {
  // Upper section, its sums, lower section, total – with small gaps.
  int pos, gap = 0;
  if (row <= Sixes) {
    pos = row;
  } else if (row == SumUpper || row == Bonus) {
    pos = row == SumUpper ? 6 : 7;
    gap = 6;
  } else if (row < CatCount) {
    pos = row + 2;
    gap = 16;
  } else {
    pos = 15;
    gap = 24;
  }
  return TableY + 28 + pos * RowH + gap;
}

class KniffelScene : public Scene {
 public:
  KniffelScene(int humans, bool computer)
      : humans_(humans),
        computer_(computer),
        game_(humans + (computer ? 1 : 0), uint32_t(std::time(nullptr))),
        rng_(uint32_t(std::time(nullptr)) + 7) {
    for (int i = 0; i < humans; i++) {
      names_.push_back(humans == 1 ? "Du" : "Spieler " + std::to_string(i + 1));
    }
    if (computer) names_.push_back("Computer");
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
    if (rolling_ > 0) {
      rolling_ -= dt;
      return;
    }
    if (computerTurn()) {
      computerStep(dt);
      return;
    }
    if (in[BtnLeft]) dieFocus_ = (dieFocus_ + 4) % 5;
    if (in[BtnRight]) dieFocus_ = (dieFocus_ + 1) % 5;
    if (in[BtnUp]) catFocus_ = (catFocus_ + CatCount - 1) % CatCount;
    if (in[BtnDown]) catFocus_ = (catFocus_ + 1) % CatCount;
    if (in[BtnY]) game_.toggleHold(dieFocus_);
    if (in[BtnA]) roll();
    if (in[BtnX]) score(catFocus_);
    if (in[BtnB]) done = true;
    if (in.tapped) tap(in.tapX, in.tapY);
  }

  void draw(Gfx& g) override {
    g.header("Kniffel");
    // Player to move and dice.
    const std::string who = names_[game_.current];
    g.text(game_.isOver() ? "Spiel vorbei" : who + (who == "Du" ? " bist dran" : " ist dran"),
           DiceX, 104, 30, theme::text);
    for (int i = 0; i < 5; i++) {
      const int x = DiceX + i * (DieSize + DieGap);
      const bool focused = i == dieFocus_ && !computerTurn() && game_.hasRolled();
      if (focused) g.roundRect(x - 6, DiceY - 6, DieSize + 12, DieSize + 12, 22, theme::focus);
      int v = game_.dice[i];
      if (rolling_ > 0 && !game_.held[i]) v = 1 + (int(rolling_ * 40) + i * 3) % 6;
      if (!game_.hasRolled()) v = 0;
      g.die(x, DiceY, DieSize, v, game_.held[i]);
    }
    if (game_.hasRolled() && game_.rollsLeft > 0) {
      g.text("Y: Würfel halten", DiceX, DiceY + DieSize + 16, 20, theme::muted);
    }
    // Roll button.
    const bool canRoll = game_.canRoll() && !computerTurn();
    g.roundRect(DiceX, 300, 300, 64, 16, canRoll ? rgb(0x2E7D32) : theme::surface);
    g.text(game_.rollsLeft == 3 ? "Würfeln" : "Nochmal würfeln", DiceX + 150, 316, 26,
           canRoll ? theme::text : theme::muted, Align::Center);
    g.text("Noch " + std::to_string(game_.rollsLeft) + "× würfeln", DiceX, 376, 22,
           theme::muted);
    if (game_.isOver()) {
      std::string w;
      for (int i : game_.winners()) w += (w.empty() ? "" : " & ") + names_[i];
      g.text(w + (game_.winners().size() > 1 ? " gewinnen!" : (w == "Du" ? " gewinnst!" : " gewinnt!")),
             DiceX, 420, 34, theme::focus);
    } else if (computerTurn()) {
      g.text("Computer überlegt …", DiceX, 420, 26, theme::muted);
    }

    // Score sheet.
    const int colW = std::min(120, (Gfx::W - 40 - TableX - LabelW) / game_.players);
    for (int p = 0; p < game_.players; p++) {
      const int x = TableX + LabelW + p * colW;
      if (p == game_.current && !game_.isOver()) {
        g.roundRect(x + 4, TableY - 4, colW - 8, rowY(Total) + RowH - TableY + 8, 10,
                    rgb(0x8C9EFF, 40));
      }
    }
    for (int row = 0; row < RowCount; row++) {
      const int y = rowY(row);
      const bool cat = row < CatCount;
      const bool focus = cat && row == catFocus_ && !computerTurn() && !game_.isOver();
      if (focus) g.roundRect(TableX - 8, y - 2, Gfx::W - 40 - TableX + 8, RowH, 8, rgb(0xFFD54F, 60));
      const char* label = cat ? kniffelLabel(row)
                              : row == SumUpper ? "Summe oben"
                              : row == Bonus    ? "Bonus (ab 63)"
                                                : "Gesamt";
      g.text(label, TableX, y + 2, 21, cat ? theme::text : theme::muted);
      for (int p = 0; p < game_.players; p++) {
        const int cx = TableX + LabelW + p * colW + colW / 2;
        const auto& sheet = game_.sheets[p];
        std::string v;
        Color c = theme::text;
        if (cat && sheet.filled(row)) {
          v = std::to_string(sheet.entries[row]);
        } else if (cat && p == game_.current && game_.hasRolled() && !game_.isOver()) {
          v = std::to_string(kniffelScore(row, game_.dice));
          c = rgb(0x9CCC65);
        } else if (row == SumUpper) {
          v = std::to_string(sheet.upperSum());
        } else if (row == Bonus) {
          v = std::to_string(sheet.bonus());
        } else if (row == Total) {
          v = std::to_string(sheet.total());
          c = theme::focus;
        }
        g.text(v, cx, y + 2, 21, c, Align::Center);
      }
    }
    for (int p = 0; p < game_.players; p++) {
      const int cx = TableX + LabelW + p * colW + colW / 2;
      std::string n = names_[p];
      if (n.rfind("Spieler ", 0) == 0) n = "S" + n.substr(8);
      if (n == "Computer") n = "CPU";
      g.text(n, cx, TableY, 20, theme::muted, Align::Center);
    }

    if (game_.isOver()) {
      g.hints({{"A", "Neues Spiel"}, {"B", "Zurück"}});
    } else {
      g.hints({{"A", "Würfeln"}, {"Y", "Halten"}, {"X", "Eintragen"}, {"B", "Zurück"}});
    }
  }

 private:
  bool computerTurn() const {
    return computer_ && game_.current == game_.players - 1 && !game_.isOver();
  }

  void roll() {
    if (!game_.canRoll()) return;
    game_.roll();
    rolling_ = 0.5;
  }

  void score(int cat) {
    if (game_.score(cat)) {
      // Next open category for the next player.
      catFocus_ = 0;
    }
  }

  void computerStep(double dt) {
    thinking_ += dt;
    if (thinking_ < 0.8) return;
    thinking_ = 0;
    if (!game_.hasRolled()) {
      roll();
      return;
    }
    if (game_.rollsLeft > 0) {
      auto holds = game_.aiHolds(rng_);
      bool all = true;
      for (bool h : holds) all &= h;
      if (!all) {
        game_.held = holds;
        roll();
        return;
      }
    }
    game_.score(game_.aiCategory());
  }

  void tap(int x, int y) {
    for (int i = 0; i < 5; i++) {
      const int dx = DiceX + i * (DieSize + DieGap);
      if (x >= dx && x < dx + DieSize && y >= DiceY && y < DiceY + DieSize) {
        dieFocus_ = i;
        game_.toggleHold(i);
        return;
      }
    }
    if (x >= DiceX && x < DiceX + 300 && y >= 300 && y < 364) {
      roll();
      return;
    }
    for (int c = 0; c < CatCount; c++) {
      if (x >= TableX - 8 && y >= rowY(c) && y < rowY(c) + RowH) {
        catFocus_ = c;
        score(c);
        return;
      }
    }
  }

  void restart() {
    game_ = KniffelGame(game_.players, uint32_t(std::time(nullptr)));
    catFocus_ = 0;
  }

  int humans_;
  bool computer_;
  KniffelGame game_;
  std::mt19937 rng_;
  std::vector<std::string> names_;
  int dieFocus_ = 0, catFocus_ = 0;
  double rolling_ = 0, thinking_ = 0;
};

}  // namespace

std::unique_ptr<Scene> makeKniffel(int humans, bool computer) {
  return std::make_unique<KniffelScene>(humans, computer);
}
