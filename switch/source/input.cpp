#include "input.hpp"

#include <cmath>

#include "gfx.hpp"

void InputReader::open() {
  for (int i = 0; i < SDL_NumJoysticks() && i < 8; i++) {
    SDL_JoystickOpen(i);
    // Motion sensor (Joy-Con / Pro Controller), if SDL offers it.
    if (SDL_IsGameController(i)) {
      if (SDL_GameController* c = SDL_GameControllerOpen(i)) {
        if (SDL_GameControllerHasSensor(c, SDL_SENSOR_ACCEL) &&
            SDL_GameControllerSetSensorEnabled(c, SDL_SENSOR_ACCEL, SDL_TRUE) == 0) {
          hasMotion_ = true;
        }
      }
    }
  }
}

void InputReader::set(Button b, bool down) {
  if (down && !down_[b]) {
    edge_[b] = true;
    repeat_[b] = 0.35;
  }
  down_[b] = down;
}

// Button numbers of the Switch SDL2 port (devkitPro switch-sdl2).
static int switchButton(int b) {
  switch (b) {
    case 0: return BtnA;
    case 1: return BtnB;
    case 2: return BtnX;
    case 3: return BtnY;
    case 6: case 8: return BtnL;   // L, ZL
    case 7: case 9: return BtnR;   // R, ZR
    case 10: return BtnPlus;
    case 11: return BtnMinus;
    case 12: case 16: return BtnLeft;   // d-pad, left stick
    case 13: case 17: return BtnUp;
    case 14: case 18: return BtnRight;
    case 15: case 19: return BtnDown;
    default: return -1;
  }
}

static int keyButton(SDL_Keycode k) {
  switch (k) {
    case SDLK_RETURN: case SDLK_SPACE: case SDLK_a: return BtnA;
    case SDLK_ESCAPE: case SDLK_BACKSPACE: case SDLK_b: return BtnB;
    case SDLK_x: return BtnX;
    case SDLK_y: return BtnY;
    case SDLK_q: return BtnL;
    case SDLK_e: return BtnR;
    case SDLK_p: case SDLK_PLUS: return BtnPlus;
    case SDLK_MINUS: return BtnMinus;
    case SDLK_UP: return BtnUp;
    case SDLK_DOWN: return BtnDown;
    case SDLK_LEFT: return BtnLeft;
    case SDLK_RIGHT: return BtnRight;
    default: return -1;
  }
}

Input InputReader::poll(double dt) {
  Input in;
  SDL_Event e;
  while (SDL_PollEvent(&e)) {
    switch (e.type) {
      case SDL_QUIT:
        in.quit = true;
        break;
      case SDL_JOYBUTTONDOWN:
      case SDL_JOYBUTTONUP: {
        const int b = switchButton(e.jbutton.button);
        if (b >= 0) set(Button(b), e.type == SDL_JOYBUTTONDOWN);
        break;
      }
      case SDL_KEYDOWN:
      case SDL_KEYUP: {
        if (e.type == SDL_KEYDOWN && e.key.repeat) break;
        const int b = keyButton(e.key.keysym.sym);
        if (b >= 0) set(Button(b), e.type == SDL_KEYDOWN);
        break;
      }
      case SDL_JOYAXISMOTION:
        if (e.jaxis.axis < 2) axis_[e.jaxis.axis] = e.jaxis.value / 32767.0;
        break;
      case SDL_CONTROLLERSENSORUPDATE:
        if (e.csensor.sensor == SDL_SENSOR_ACCEL) {
          for (int k = 0; k < 3; k++) accel_[k] = e.csensor.data[k];
        }
        break;
      case SDL_FINGERDOWN:
        fingerDown_ = true;
        moved_ = false;
        startX_ = e.tfinger.x * Gfx::W;
        startY_ = e.tfinger.y * Gfx::H;
        touchX_ = int(startX_);
        touchY_ = int(startY_);
        break;
      case SDL_FINGERMOTION: {
        if (!fingerDown_) break;
        const float x = e.tfinger.x * Gfx::W, y = e.tfinger.y * Gfx::H;
        touchX_ = int(x);
        touchY_ = int(y);
        const float dx = x - startX_, dy = y - startY_;
        if (std::hypot(dx, dy) > 40) {
          moved_ = true;
          if (std::fabs(dx) > std::fabs(dy)) {
            in.swipeX = dx > 0 ? 1 : -1;
          } else {
            in.swipeY = dy > 0 ? 1 : -1;
          }
          // Keep swiping without lifting the finger.
          startX_ = x;
          startY_ = y;
        }
        break;
      }
      case SDL_FINGERUP:
        if (fingerDown_ && !moved_) {
          in.tapped = true;
          in.tapX = int(e.tfinger.x * Gfx::W);
          in.tapY = int(e.tfinger.y * Gfx::H);
        }
        fingerDown_ = false;
        break;
#ifndef __SWITCH__
      case SDL_MOUSEBUTTONUP:
        if (e.button.which == SDL_TOUCH_MOUSEID) break;
        in.tapped = true;
        in.tapX = e.button.x;
        in.tapY = e.button.y;
        break;
#endif
      default:
        break;
    }
  }
  // Analog stick with a dead zone; the arrow keys count as full deflection.
  for (int k = 0; k < 2; k++) {
    double v = axis_[k];
    if (std::fabs(v) < 0.12) v = 0;
    (k == 0 ? in.stickX : in.stickY) = v;
  }
  if (down_[BtnLeft] && in.stickX == 0) in.stickX = -1;
  if (down_[BtnRight] && in.stickX == 0) in.stickX = 1;
  if (down_[BtnUp] && in.stickY == 0) in.stickY = -1;
  if (down_[BtnDown] && in.stickY == 0) in.stickY = 1;
  in.hasMotion = hasMotion_;
  in.accelX = accel_[0];
  in.accelY = accel_[1];
  in.accelZ = accel_[2];
  in.touching = fingerDown_;
  in.touchX = touchX_;
  in.touchY = touchY_;
  for (int b = 0; b < BtnCount; b++) {
    in.held[b] = down_[b];
    in.pressed[b] = edge_[b];
    edge_[b] = false;
    // Directions repeat while held, for moving a cursor.
    const bool dir = b == BtnUp || b == BtnDown || b == BtnLeft || b == BtnRight;
    if (dir && down_[b] && !in.pressed[b]) {
      repeat_[b] -= dt;
      if (repeat_[b] <= 0) {
        in.pressed[b] = true;
        repeat_[b] = 0.09;
      }
    }
  }
  return in;
}
