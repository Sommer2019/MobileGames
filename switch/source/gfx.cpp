#include <algorithm>
#include "gfx.hpp"

#include <cmath>
#include <cstdlib>
#include <vector>

#ifdef __SWITCH__
#include <switch.h>
#endif

bool Gfx::init() {
  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER |
               SDL_INIT_SENSOR | SDL_INIT_EVENTS) < 0) {
    return false;
  }
  if (TTF_Init() < 0) return false;
#ifdef __SWITCH__
  plInitialize(PlServiceType_User);
#endif
  window_ = SDL_CreateWindow("Mobile Games", SDL_WINDOWPOS_CENTERED,
                             SDL_WINDOWPOS_CENTERED, W, H, 0);
  if (!window_) return false;
  renderer_ = SDL_CreateRenderer(
      window_, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (!renderer_) renderer_ = SDL_CreateRenderer(window_, -1, 0);
  if (!renderer_) return false;
  SDL_SetRenderDrawBlendMode(renderer_, SDL_BLENDMODE_BLEND);
  return font(24) != nullptr;
}

void Gfx::shutdown() {
  for (auto& [key, c] : cache_) SDL_DestroyTexture(c.texture);
  cache_.clear();
  for (auto& [size, f] : fonts_) TTF_CloseFont(f);
  fonts_.clear();
  if (renderer_) SDL_DestroyRenderer(renderer_);
  if (window_) SDL_DestroyWindow(window_);
#ifdef __SWITCH__
  plExit();
#endif
  TTF_Quit();
  SDL_Quit();
}

TTF_Font* Gfx::font(int size, bool symbols) {
  const int key = symbols ? -size : size;
  auto it = fonts_.find(key);
  if (it != fonts_.end()) return it->second;
  TTF_Font* f = nullptr;
  if (symbols) {
#ifdef __SWITCH__
    f = TTF_OpenFont("romfs:/DejaVuSans.ttf", size);
#else
    const char* dir = std::getenv("MG_ROMFS");
    f = TTF_OpenFont((std::string(dir ? dir : "romfs") + "/DejaVuSans.ttf").c_str(), size);
#endif
    if (f) fonts_[key] = f;
    return f ? f : font(size);
  }
#ifdef __SWITCH__
  // The console's own system font (has umlauts), no font file needed.
  PlFontData data;
  if (R_SUCCEEDED(plGetSharedFontByType(&data, PlSharedFontType_Standard))) {
    f = TTF_OpenFontRW(SDL_RWFromConstMem(data.address, data.size), 1, size);
  }
#else
  const char* path = std::getenv("MG_FONT");
  f = TTF_OpenFont(path ? path : "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                   size);
#endif
  if (f) fonts_[key] = f;
  return f;
}

void Gfx::setColor(Color c) {
  SDL_SetRenderDrawColor(renderer_, c.r, c.g, c.b, c.a);
}

void Gfx::clear(Color c) {
  setColor(c);
  SDL_RenderClear(renderer_);
}

void Gfx::present() {
  SDL_RenderPresent(renderer_);
  frame_++;
  // Drop text that was not drawn for a while.
  if (cache_.size() > 300) {
    for (auto it = cache_.begin(); it != cache_.end();) {
      if (frame_ - it->second.lastUse > 120) {
        SDL_DestroyTexture(it->second.texture);
        it = cache_.erase(it);
      } else {
        ++it;
      }
    }
  }
}

void Gfx::rect(int x, int y, int w, int h, Color c) {
  setColor(c);
  SDL_Rect r{x, y, w, h};
  SDL_RenderFillRect(renderer_, &r);
}

void Gfx::roundRect(int x, int y, int w, int h, int radius, Color c) {
  radius = std::min(radius, std::min(w, h) / 2);
  setColor(c);
  // Rows of the rounded corners, then the middle block.
  for (int i = 0; i < radius; i++) {
    const double dy = radius - i - 0.5;
    const int inset =
        radius - int(std::lround(std::sqrt(double(radius * radius) - dy * dy)));
    SDL_Rect top{x + inset, y + i, w - 2 * inset, 1};
    SDL_Rect bottom{x + inset, y + h - 1 - i, w - 2 * inset, 1};
    SDL_RenderFillRect(renderer_, &top);
    SDL_RenderFillRect(renderer_, &bottom);
  }
  SDL_Rect mid{x, y + radius, w, h - 2 * radius};
  SDL_RenderFillRect(renderer_, &mid);
}

void Gfx::circle(int cx, int cy, int radius, Color c) {
  setColor(c);
  for (int dy = -radius; dy <= radius; dy++) {
    const int dx = int(std::sqrt(double(radius * radius - dy * dy)));
    SDL_RenderDrawLine(renderer_, cx - dx, cy + dy, cx + dx, cy + dy);
  }
}

void Gfx::ring(int cx, int cy, int radius, int thickness, Color c) {
  setColor(c);
  const int inner = radius - thickness;
  for (int dy = -radius; dy <= radius; dy++) {
    const int outerDx = int(std::sqrt(double(radius * radius - dy * dy)));
    if (std::abs(dy) >= inner) {
      SDL_RenderDrawLine(renderer_, cx - outerDx, cy + dy, cx + outerDx, cy + dy);
      continue;
    }
    const int innerDx = int(std::sqrt(double(inner * inner - dy * dy)));
    SDL_RenderDrawLine(renderer_, cx - outerDx, cy + dy, cx - innerDx, cy + dy);
    SDL_RenderDrawLine(renderer_, cx + innerDx, cy + dy, cx + outerDx, cy + dy);
  }
}

void Gfx::line(int x1, int y1, int x2, int y2, int thickness, Color c) {
  const double len = std::hypot(x2 - x1, y2 - y1);
  const int steps = std::max(1, int(len));
  for (int i = 0; i <= steps; i++) {
    const double t = double(i) / steps;
    circle(int(x1 + (x2 - x1) * t), int(y1 + (y2 - y1) * t), thickness / 2, c);
  }
}

int Gfx::textWidth(const std::string& s, int size) {
  int w = 0, h = 0;
  if (TTF_Font* f = font(size)) TTF_SizeUTF8(f, s.c_str(), &w, &h);
  return w;
}

int Gfx::text(const std::string& s, int x, int y, int size, Color c,
              Align align) {
  if (s.empty()) return 0;
  const uint32_t packed = (uint32_t(c.r) << 24) | (c.g << 16) | (c.b << 8) | c.a;
  auto key = std::make_tuple(s, size, packed);
  auto it = cache_.find(key);
  if (it == cache_.end()) {
    TTF_Font* f = font(size);
    if (!f) return 0;
    SDL_Surface* surf =
        TTF_RenderUTF8_Blended(f, s.c_str(), SDL_Color{c.r, c.g, c.b, c.a});
    if (!surf) return 0;
    SDL_Texture* tex = SDL_CreateTextureFromSurface(renderer_, surf);
    it = cache_.emplace(key, Cached{tex, surf->w, surf->h, frame_}).first;
    SDL_FreeSurface(surf);
  }
  Cached& t = it->second;
  t.lastUse = frame_;
  int left = x;
  if (align == Align::Center) left = x - t.w / 2;
  if (align == Align::Right) left = x - t.w;
  SDL_Rect dst{left, y, t.w, t.h};
  SDL_RenderCopy(renderer_, t.texture, nullptr, &dst);
  return t.w;
}

int Gfx::hint(const std::string& button, const std::string& label, int x,
              int y) {
  const int r = 15;
  circle(x + r, y + r, r, theme::text);
  // Bundled font: the letters were not visible with the system font.
  symbol(button, x + r, y + r, 19, theme::background);
  const int w = text(label, x + 2 * r + 8, y + 2, 22, theme::text);
  return 2 * r + 8 + w;
}

void Gfx::hints(
    std::initializer_list<std::pair<std::string, std::string>> list) {
  // Right aligned like on the Switch home menu.
  int total = 0;
  for (auto& [b, l] : list) total += 30 + 8 + textWidth(l, 22) + 28;
  int x = W - 32 - total + 28;
  rect(0, H - 56, W, 1, theme::surfaceHigh);
  for (auto& [b, l] : list) x += hint(b, l, x, H - 44) + 28;
}

void Gfx::header(const std::string& title, const std::string& right) {
  text(title, 48, 22, 36, theme::text);
  if (!right.empty()) text(right, W - 48, 30, 26, theme::muted, Align::Right);
  rect(0, 80, W, 1, theme::surfaceHigh);
}

void Gfx::symbol(const std::string& s, int cx, int cy, int size, Color c) {
  TTF_Font* f = font(size, true);
  if (!f || s.empty()) return;
  const uint32_t packed = (uint32_t(c.r) << 24) | (c.g << 16) | (c.b << 8) | c.a;
  // Separate cache entries from normal text of the same size.
  auto key = std::make_tuple("\x01" + s, size, packed);
  auto it = cache_.find(key);
  if (it == cache_.end()) {
    SDL_Surface* surf = TTF_RenderUTF8_Blended(f, s.c_str(), SDL_Color{c.r, c.g, c.b, c.a});
    if (!surf) return;
    SDL_Texture* tex = SDL_CreateTextureFromSurface(renderer_, surf);
    it = cache_.emplace(key, Cached{tex, surf->w, surf->h, frame_}).first;
    SDL_FreeSurface(surf);
  }
  Cached& t = it->second;
  t.lastUse = frame_;
  SDL_Rect dst{cx - t.w / 2, cy - t.h / 2, t.w, t.h};
  SDL_RenderCopy(renderer_, t.texture, nullptr, &dst);
}

void Gfx::die(int x, int y, int size, int value, bool held) {
  roundRect(x, y + size / 18, size, size, size / 5, rgb(0x000000, 90));
  roundRect(x, y, size, size, size / 5, held ? rgb(0xFFE082) : rgb(0xFAFAFA));
  static const int pips[7][6][2] = {
      {},
      {{1, 1}},
      {{0, 0}, {2, 2}},
      {{0, 0}, {1, 1}, {2, 2}},
      {{0, 0}, {2, 0}, {0, 2}, {2, 2}},
      {{0, 0}, {2, 0}, {1, 1}, {0, 2}, {2, 2}},
      {{0, 0}, {2, 0}, {0, 1}, {2, 1}, {0, 2}, {2, 2}},
  };
  const int margin = size * 23 / 100, gap = (size - 2 * margin) / 2;
  for (int k = 0; k < value && value <= 6; k++) {
    circle(x + margin + pips[value][k][0] * gap, y + margin + pips[value][k][1] * gap,
           size / 11, rgb(0x212121));
  }
}

void Gfx::polygon(const float* xs, const float* ys, int n, Color c) {
  if (n < 3) return;
  std::vector<SDL_Vertex> v(static_cast<size_t>(n));
  for (int i = 0; i < n; i++) {
    v[size_t(i)].position = {xs[i], ys[i]};
    v[size_t(i)].color = {c.r, c.g, c.b, c.a};
    v[size_t(i)].tex_coord = {0, 0};
  }
  std::vector<int> idx;
  for (int i = 1; i + 1 < n; i++) {
    idx.push_back(0);
    idx.push_back(i);
    idx.push_back(i + 1);
  }
  SDL_RenderGeometry(renderer_, nullptr, v.data(), n, idx.data(), int(idx.size()));
}
