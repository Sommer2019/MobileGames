// Screens of the app. The app keeps a stack: a scene can open another one
// ([push]) or close itself ([done]).
#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "gfx.hpp"
#include "input.hpp"

class Scene {
 public:
  virtual ~Scene() = default;
  virtual void update(const Input& in, double dt) = 0;
  virtual void draw(Gfx& g) = 0;

  bool done = false;
  std::unique_ptr<Scene> push;
};

// Main menu with the game tiles.
std::unique_ptr<Scene> makeMenu();

// A list of choices, e.g. "2 Spieler" / "Gegen Computer".
struct Choice {
  std::string label;
  std::string detail;
  std::function<std::unique_ptr<Scene>()> open;
};
std::unique_ptr<Scene> makeChoices(std::string title, Color color,
                                   std::vector<Choice> choices);

std::unique_ptr<Scene> makeSnake(bool wrap);
std::unique_ptr<Scene> makeConnectFour(int players, bool vsComputer);
std::unique_ptr<Scene> makeCheckers(bool vsComputer);
std::unique_ptr<Scene> makeDiceCup();
std::unique_ptr<Scene> makeChess(bool vsComputer);
std::unique_ptr<Scene> makeMill(bool vsComputer);
std::unique_ptr<Scene> makeKniffel(int humans, bool computer);
std::unique_ptr<Scene> makeBattleship(bool vsComputer);
std::unique_ptr<Scene> makeSolitaire(int drawCount);
std::unique_ptr<Scene> makeMahjong(bool tower);
std::unique_ptr<Scene> makeSecrets();
std::unique_ptr<Scene> makeLabyrinth();
std::unique_ptr<Scene> makeDarts(int mode, int players);  // 0 = 501, 1 = 301, 2 = Uhr
std::unique_ptr<Scene> makeBilliard(int mode);  // 0 = 8 zum Schluss, 1 = Reihenfolge, 2 = zu zweit
