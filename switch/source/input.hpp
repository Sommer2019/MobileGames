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
  // Left stick (or arrow keys on the PC), -1..1 with a small dead zone.
  double stickX = 0, stickY = 0;
  // Gravity from the controller's motion sensor (m/s²), if it has one.
  bool hasMotion = false;
  double accelX = 0, accelY = 0, accelZ = 0;
  // Finger on the screen right now (position in pixels).
  bool touching = false;
  int touchX = 0, touchY = 0;

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
  double axis_[2] = {};
  bool hasMotion_ = false;
  double accel_[3] = {};
  int touchX_ = 0, touchY_ = 0;
  bool fingerDown_ = false;
  float startX_ = 0, startY_ = 0;
  bool moved_ = false;
};
