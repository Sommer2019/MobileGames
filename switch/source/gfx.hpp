// Drawing on the 1280×720 screen with SDL2 (also used for the PC build).
#pragma once

#include <SDL.h>
#include <SDL_ttf.h>

#include <map>
#include <string>
#include <tuple>

struct Color {
  uint8_t r, g, b, a = 255;
};

constexpr Color rgb(uint32_t hex, uint8_t a = 255) {
  return {uint8_t(hex >> 16), uint8_t(hex >> 8), uint8_t(hex), a};
}

namespace theme {
constexpr Color background = rgb(0x1C1B22);
constexpr Color surface = rgb(0x2A2833);
constexpr Color surfaceHigh = rgb(0x3A3746);
constexpr Color text = rgb(0xF1EEF6);
constexpr Color muted = rgb(0xA9A4B6);
constexpr Color accent = rgb(0x8C9EFF);
constexpr Color focus = rgb(0xFFD54F);
}  // namespace theme

enum class Align { Left, Center, Right };

class Gfx {
 public:
  static constexpr int W = 1280, H = 720;

  bool init();
  void shutdown();

  void clear(Color c);
  void present();

  void rect(int x, int y, int w, int h, Color c);
  void roundRect(int x, int y, int w, int h, int radius, Color c);
  void circle(int cx, int cy, int radius, Color c);
  void ring(int cx, int cy, int radius, int thickness, Color c);
  void line(int x1, int y1, int x2, int y2, int thickness, Color c);

  // Draws text; returns its width. y is the top of the line.
  int text(const std::string& s, int x, int y, int size, Color c,
           Align align = Align::Left);
  int textWidth(const std::string& s, int size);
  // Text in the bundled DejaVu font (card suits ♠♥♦♣, chess pieces ♔♚ …),
  // centred on (cx, cy).
  void symbol(const std::string& s, int cx, int cy, int size, Color c);

  // A die with [value] pips; held dice are yellow.
  void die(int x, int y, int size, int value, bool held);
  // A round controller button ("A", "B", "+" …) followed by a label.
  int hint(const std::string& button, const std::string& label, int x, int y);
  // Hints at the bottom right, e.g. {{"A", "Werfen"}, {"B", "Zurück"}}.
  void hints(std::initializer_list<std::pair<std::string, std::string>> list);
  // Title bar at the top.
  void header(const std::string& title, const std::string& right = "");

  SDL_Renderer* renderer() const { return renderer_; }

 private:
  TTF_Font* font(int size, bool symbols = false);
  void setColor(Color c);

  SDL_Window* window_ = nullptr;
  SDL_Renderer* renderer_ = nullptr;
  std::map<int, TTF_Font*> fonts_;  // key: size, negative = symbol font
  struct Cached {
    SDL_Texture* texture;
    int w, h;
    uint32_t lastUse;
  };
  std::map<std::tuple<std::string, int, uint32_t>, Cached> cache_;
  uint32_t frame_ = 0;
};
