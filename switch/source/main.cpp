// Mobile Games for the Nintendo Switch (homebrew, offline): the local
// games of the app for one console.
#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "gfx.hpp"
#include "input.hpp"
#include "scene.hpp"

#ifdef __SWITCH__
#include <switch.h>
#endif

int main(int, char**) {
#ifdef __SWITCH__
  romfsInit();  // font with card suits and chess pieces
#endif
  Gfx gfx;
  if (!gfx.init()) return 1;
  InputReader input;
  input.open();

  std::vector<std::unique_ptr<Scene>> stack;
  stack.push_back(makeMenu());
#ifndef __SWITCH__
  // Test aid: open a game right away (snake, c4, c4ai, checkers, dice).
  if (const char* start = SDL_getenv("MG_START")) {
    const std::string s = start;
    if (s == "snake") stack.push_back(makeSnake(false));
    if (s == "c4") stack.push_back(makeConnectFour(4, false));
    if (s == "c4ai") stack.push_back(makeConnectFour(2, true));
    if (s == "checkers") stack.push_back(makeCheckers(true));
    if (s == "dice") stack.push_back(makeDiceCup());
    if (s == "chess") stack.push_back(makeChess(true));
    if (s == "mill") stack.push_back(makeMill(true));
    if (s == "kniffel") stack.push_back(makeKniffel(1, true));
    if (s == "battleship") stack.push_back(makeBattleship(true));
    if (s == "solitaire") stack.push_back(makeSolitaire(1));
  }
#endif
  Uint64 last = SDL_GetPerformanceCounter();
  const double freq = double(SDL_GetPerformanceFrequency());

  while (!stack.empty()) {
#ifdef __SWITCH__
    if (!appletMainLoop()) break;
#endif
    const Uint64 now = SDL_GetPerformanceCounter();
    const double dt = std::min(0.1, (now - last) / freq);
    last = now;

#ifndef __SWITCH__
    // Test aid: MG_KEYS="a,right,a" presses one key every 10 frames.
    if (const char* keys = SDL_getenv("MG_KEYS")) {
      static std::vector<SDL_Keycode> script;
      static int frame = 0;
      if (frame == 0) {
        std::string all = keys, k;
        for (size_t i = 0; i <= all.size(); i++) {
          if (i == all.size() || all[i] == ',') {
            const SDL_Keycode code = SDL_GetKeyFromName(k.c_str());
            if (code != SDLK_UNKNOWN) script.push_back(code);
            k.clear();
          } else {
            k += all[i];
          }
        }
      }
      const int step = frame / 10, phase = frame % 10;
      if (step < (int)script.size() && (phase == 0 || phase == 2)) {
        SDL_Event e{};
        e.type = phase == 0 ? SDL_KEYDOWN : SDL_KEYUP;
        e.key.keysym.sym = script[step];
        SDL_PushEvent(&e);
      }
      frame++;
    }
#endif
    const Input in = input.poll(dt);
    if (in.quit) break;
    Scene& top = *stack.back();
    top.update(in, dt);
    if (top.push) {
      stack.push_back(std::move(top.push));
    } else if (top.done) {
      stack.pop_back();
    }
    if (stack.empty()) break;

    gfx.clear(theme::background);
    stack.back()->draw(gfx);
    gfx.present();
#ifndef __SWITCH__
    if (const char* shot = SDL_getenv("MG_SCREENSHOT")) {
      // Test aid: save a screenshot after N frames, then quit.
      static int frames = 0;
      if (++frames == SDL_atoi(SDL_getenv("MG_FRAMES") ? SDL_getenv("MG_FRAMES") : "30")) {
        SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, Gfx::W, Gfx::H, 32,
                                                        SDL_PIXELFORMAT_ARGB8888);
        SDL_RenderReadPixels(gfx.renderer(), nullptr, SDL_PIXELFORMAT_ARGB8888,
                             s->pixels, s->pitch);
        SDL_SaveBMP(s, shot);
        SDL_FreeSurface(s);
        break;
      }
    }
#endif
  }
  stack.clear();
  gfx.shutdown();
#ifdef __SWITCH__
  romfsExit();
#endif
  return 0;
}
