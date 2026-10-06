// Joy-Cons / Pro Controller on the Switch, keyboard on the PC, plus the
// touch screen (handheld mode) or mouse.
#pragma once

#include <SDL.h>

enum Button {
  BtnA, BtnB, BtnX, BtnY, BtnL, BtnR, BtnPlus, BtnMinus,
  BtnUp, BtnDown, BtnLeft, BtnRight, BtnCount
};

struct Input {
  bool pressed[BtnCount] = {};  // this frame (directions with key repeat)
  bool held[BtnCount] = {};
  bool quit = false;
  bool tapped = false;          // finger lifted without moving much
  int tapX = 0, tapY = 0;
  int swipeX = 0, swipeY = 0;   // -1/0/1 once a finger moved far enough

  bool operator[](Button b) const { return pressed[b]; }
};

class InputReader {
 public:
  void open();
  // Reads all events of this frame.
  Input poll(double dt);

 private:
  void set(Button b, bool down);
  bool down_[BtnCount] = {};
  bool edge_[BtnCount] = {};
  double repeat_[BtnCount] = {};
  bool fingerDown_ = false;
  float startX_ = 0, startY_ = 0;
  bool moved_ = false;
};
