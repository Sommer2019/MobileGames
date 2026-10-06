// Secret extras, unlocked with the Konami code in the main menu
// (↑↑↓↓←→←→ B A +) – the same extras as in the app.
#pragma once

#include <string>

#include "save.hpp"

enum class Secret {
  Retro,          // Snake im Retro-Handy-Look, Pixel-Billard
  Disco,          // Billardkugeln wechseln beim Rollen die Farbe
  RubberBall,     // Labyrinth-Kugel springt von den Wänden ab
  Nightmare,      // Labyrinth spiegelverkehrt, mehr Schwung
  Grandmaster,    // Schach und Dame: stärkerer Computer
  LuckyComputer,  // Kniffel: der Computer würfelt einmal verdächtig gut
  LabyrinthEasy,  // alle Labyrinth-Level frei
  Count
};

namespace secrets {

inline const char* title(Secret s) {
  static const char* t[] = {"Retro-Modus", "Disco-Kugeln", "Gummiball", "Albtraum-Labyrinth",
                            "Großmeister", "Glückspilz-Computer", "Easy Mode Labyrinth"};
  return t[int(s)];
}

inline const char* description(Secret s) {
  static const char* d[] = {
      "Snake im Retro-Handy-Look, Pixel-Billard",
      "Billardkugeln wechseln beim Rollen die Farbe",
      "Die Labyrinth-Kugel springt von den Wänden ab",
      "Steuerung spiegelverkehrt, die Kugel hat mehr Schwung",
      "Schach und Dame: der Computer spielt stärker",
      "Würfelkönig: der Computer würfelt einmal pro Spiel verdächtig gut",
      "Alle Labyrinth-Level freigeschaltet"};
  return d[int(s)];
}

inline std::string key(Secret s) { return "secret." + std::to_string(int(s)); }

inline bool unlocked() { return Save::get().getInt("secret.konami") == 1; }

inline bool on(Secret s) { return unlocked() && Save::get().getInt(key(s)) == 1; }

inline void set(Secret s, bool value) { Save::get().set(key(s), value ? 1 : 0); }

// Returns true the first time.
inline bool unlock() {
  if (unlocked()) return false;
  Save::get().set("secret.konami", 1);
  set(Secret::Retro, true);
  return true;
}

}  // namespace secrets
