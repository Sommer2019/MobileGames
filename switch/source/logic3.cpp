#include "logic3.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <set>

// -------------------------------------------------------------------- Mahjong

std::vector<MjSlot> mahjongPyramid() {
  std::vector<MjSlot> s;
  for (int y = 0; y < 6; y++)
    for (int x = 0; x < 12; x++) s.push_back({x * 2, y * 2, 0});
  for (int y = 0; y < 4; y++)
    for (int x = 0; x < 8; x++) s.push_back({4 + x * 2, 2 + y * 2, 1});
  for (int y = 0; y < 2; y++)
    for (int x = 0; x < 6; x++) s.push_back({6 + x * 2, 4 + y * 2, 2});
  for (int y = 0; y < 2; y++)
    for (int x = 0; x < 2; x++) s.push_back({10 + x * 2, 4 + y * 2, 3});
  return s;
}

std::vector<MjSlot> mahjongTower() {
  std::vector<MjSlot> s;
  for (int y = 0; y < 10; y++)
    for (int x = 0; x < 6; x++) s.push_back({x * 2, y * 2, 0});
  for (int y = 0; y < 8; y++)
    for (int x = 0; x < 4; x++) s.push_back({2 + x * 2, 2 + y * 2, 1});
  for (int y = 0; y < 6; y++)
    for (int x = 0; x < 2; x++) s.push_back({4 + x * 2, 4 + y * 2, 2});
  for (int y = 0; y < 2; y++)
    for (int x = 0; x < 2; x++) s.push_back({4 + x * 2, 8 + y * 2, 3});
  return s;
}

static std::vector<MjFace> allFaces() {
  std::vector<MjFace> f;
  for (int s = 0; s < 3; s++)
    for (int r = 0; r < 9; r++) f.push_back({s, r});
  for (int r = 0; r < 4; r++) f.push_back({3, r});
  for (int r = 0; r < 3; r++) f.push_back({4, r});
  return f;
}

Mahjong::Mahjong(std::vector<MjSlot> layout, uint32_t seed) : slots(std::move(layout)) {
  std::mt19937 rng(seed);
  const auto all = allFaces();
  const size_t n = slots.size();
  // Deal by removing random free pairs, so the game is always solvable.
  while (true) {
    faces.assign(n, MjFace{});
    removed.assign(n, false);
    std::vector<MjFace> pairs;
    for (size_t i = 0; i < n / 2; i++) pairs.push_back(all[(i / 2) % all.size()]);
    std::shuffle(pairs.begin(), pairs.end(), rng);
    bool ok = true;
    for (auto& face : pairs) {
      std::vector<int> free;
      for (size_t i = 0; i < n; i++) {
        if (!removed[i] && isFree(int(i))) free.push_back(int(i));
      }
      if (free.size() < 2) {
        ok = false;
        break;
      }
      std::shuffle(free.begin(), free.end(), rng);
      faces[free[0]] = face;
      faces[free[1]] = face;
      removed[free[0]] = removed[free[1]] = true;
    }
    if (ok) break;
  }
  removed.assign(n, false);
}

int Mahjong::remaining() const {
  return int(std::count(removed.begin(), removed.end(), false));
}

bool Mahjong::isFree(int t) const {
  if (removed[t]) return false;
  const MjSlot& a = slots[t];
  bool left = false, right = false;
  for (size_t i = 0; i < slots.size(); i++) {
    if (removed[i] || int(i) == t) continue;
    const MjSlot& b = slots[i];
    if (b.z > a.z && std::abs(a.x - b.x) < 2 && std::abs(a.y - b.y) < 2) return false;
    if (b.z == a.z && std::abs(a.y - b.y) < 2) {
      if (b.x == a.x - 2) left = true;
      if (b.x == a.x + 2) right = true;
    }
  }
  return !(left && right);
}

bool Mahjong::canMatch(int a, int b) const {
  return a != b && faces[a] == faces[b] && isFree(a) && isFree(b);
}

bool Mahjong::match(int a, int b) {
  if (!canMatch(a, b)) return false;
  removed[a] = removed[b] = true;
  history.push_back({a, b});
  return true;
}

bool Mahjong::undo() {
  if (history.empty()) return false;
  auto [a, b] = history.back();
  history.pop_back();
  removed[a] = removed[b] = false;
  return true;
}

std::optional<std::pair<int, int>> Mahjong::hint() const {
  std::vector<int> free;
  for (size_t i = 0; i < slots.size(); i++) {
    if (isFree(int(i))) free.push_back(int(i));
  }
  for (size_t i = 0; i < free.size(); i++) {
    for (size_t j = i + 1; j < free.size(); j++) {
      if (faces[free[i]] == faces[free[j]]) return std::make_pair(free[i], free[j]);
    }
  }
  return std::nullopt;
}

void Mahjong::shuffleRemaining(std::mt19937& rng) {
  std::vector<int> left;
  for (size_t i = 0; i < slots.size(); i++) {
    if (!removed[i]) left.push_back(int(i));
  }
  for (int attempt = 0; attempt < 50; attempt++) {
    std::vector<MjFace> f;
    for (int i : left) f.push_back(faces[i]);
    std::shuffle(f.begin(), f.end(), rng);
    for (size_t i = 0; i < left.size(); i++) faces[left[i]] = f[i];
    if (hint()) return;
  }
}

// ------------------------------------------------------------------ Labyrinth

namespace {
constexpr double T = 0.025;  // wall thickness

std::vector<LWall> frameWalls() {
  return {{0, 0, BoardW, T}, {0, BoardH - T, BoardW, BoardH}, {0, 0, T, BoardH},
          {BoardW - T, 0, BoardW, BoardH}};
}
LWall hw(double x1, double x2, double y) { return {x1, y - T / 2, x2, y + T / 2}; }
LWall vw(double x, double y1, double y2) { return {x - T / 2, y1, x + T / 2, y2}; }

std::vector<LWall> with(std::vector<LWall> a, std::initializer_list<LWall> b) {
  a.insert(a.end(), b.begin(), b.end());
  return a;
}

std::vector<LLevel> handmade() {
  std::vector<LLevel> l;
  l.push_back({"Aufwärmen", 0.15, 0.12, {0.85, 1.48},
               with(frameWalls(), {hw(0, 0.7, 0.45), hw(0.3, 1, 0.9), hw(0, 0.7, 1.25)}),
               {}});
  l.push_back({"Erste Löcher", 0.12, 0.12, {0.12, 1.48},
               with(frameWalls(), {hw(0, 0.72, 0.4), hw(0.28, 1, 0.8), hw(0, 0.72, 1.2)}),
               {{0.88, 0.2}, {0.5, 0.6}, {0.12, 1.0}, {0.55, 1.4}}});
  l.push_back({"Zickzack", 0.1, 0.1, {0.9, 1.5},
               with(frameWalls(), {vw(0.25, 0, 1.3), vw(0.5, 0.3, 1.6), vw(0.75, 0, 1.3)}),
               {{0.125, 0.8}, {0.375, 0.2}, {0.375, 1.0}, {0.625, 0.55}, {0.625, 1.2},
                {0.875, 0.75}}});
  l.push_back({"Kammern", 0.5, 0.1, {0.5, 0.85},
               with(frameWalls(), {hw(0.2, 0.8, 0.3), vw(0.2, 0.3, 1.3), vw(0.8, 0.3, 1.3),
                                   hw(0.2, 0.42, 1.3), hw(0.58, 0.8, 1.3), hw(0.35, 0.42, 0.55),
                                   hw(0.58, 0.65, 0.55), vw(0.35, 0.55, 1.05),
                                   vw(0.65, 0.55, 1.05), hw(0.35, 0.65, 1.05)}),
               {{0.06, 0.8, 0.035}, {0.94, 1.0, 0.035}, {0.5, 1.45, 0.035},
                {0.5, 1.15, 0.035}, {0.27, 0.4, 0.035}, {0.73, 0.45, 0.035}}});
  l.push_back({"Meisterstück", 0.08, 1.52, {0.92, 0.08, 0.04},
               with(frameWalls(), {hw(0, 0.8, 1.38), hw(0.2, 1, 1.12), hw(0, 0.8, 0.86),
                                   hw(0.2, 1, 0.6), hw(0, 0.8, 0.34), vw(0.5, 1.12, 1.25),
                                   vw(0.5, 0.6, 0.73)}),
               {{0.35, 1.48}, {0.92, 1.3}, {0.3, 1.25}, {0.7, 1.0}, {0.08, 0.98},
                {0.4, 0.74}, {0.92, 0.75}, {0.6, 0.47}, {0.08, 0.48}, {0.5, 0.2},
                {0.25, 0.1}}});
  return l;
}

std::vector<LLevel> edgeLevels() {
  std::vector<LLevel> l;
  l.push_back({"Ohne Rand", 0.5, 0.12, {0.5, 1.45},
               {hw(0.2, 0.8, 0.45), hw(0.2, 0.8, 0.95)},
               {{0.5, 0.7, 0.05}, {0.5, 1.2, 0.05}}, false});
  std::vector<LHole> rim;
  for (int i = 0; i < 10; i++) rim.push_back({0.05 + i * 0.1, 0.04, 0.04});
  for (int i = 0; i < 10; i++) rim.push_back({0.05 + i * 0.1, 1.56, 0.04});
  for (int i = 1; i < 16; i++) rim.push_back({0.04, i * 0.1, 0.04});
  for (int i = 1; i < 16; i++) rim.push_back({0.96, i * 0.1, 0.04});
  rim.push_back({0.8, 0.75, 0.04});
  rim.push_back({0.2, 1.25, 0.04});
  rim.erase(std::remove_if(rim.begin(), rim.end(),
                           [](const LHole& h) { return h.y > 1.5 && std::abs(h.x - 0.8) < 0.1; }),
            rim.end());
  l.push_back({"Lochrand", 0.2, 0.15, {0.8, 1.45}, {hw(0.1, 0.65, 0.5), hw(0.35, 0.9, 1.0)},
               rim, false});
  std::vector<LHole> slalom;
  for (int i = 0; i < 7; i++) slalom.push_back({i % 2 == 0 ? 0.32 : 0.68, 0.25 + i * 0.18, 0.12});
  l.push_back({"Slalom", 0.5, 0.08, {0.5, 1.52}, {}, slalom, false});
  return l;
}

struct MazeSpec {
  const char* name;
  int cols, rows;
  double holeShare, pathTraps;
};
const MazeSpec Mazes[] = {
    {"Irrgarten", 4, 6, 0.0, 0.0},       {"Sackgassen", 4, 7, 0.35, 0.45},
    {"Wendeltreppe", 5, 7, 0.4, 0.6},    {"Fallenstellerei", 5, 8, 0.55, 0.75},
    {"Holzwurm", 5, 9, 0.6, 0.85},       {"Engpass", 6, 9, 0.6, 0.9},
    {"Lochfraß", 6, 10, 0.7, 0.95},      {"Schweizer Käse", 6, 10, 0.85, 1.0},
    {"Geduldsprobe", 7, 11, 0.7, 1.0},   {"Nervenkitzel", 7, 11, 0.85, 1.0},
    {"Zitterpartie", 7, 11, 1.0, 1.0},   {"Großmeister", 7, 11, 1.0, 1.0},
};
struct FieldSpec {
  const char* name;
  int cols, rows;
  bool frame;
  double pathTraps;
};
const FieldSpec Fields[] = {
    {"Lochfeld", 4, 6, true, 0.6},          {"Pfad der Löcher", 5, 7, true, 0.8},
    {"Freier Fall", 4, 7, false, 0.8},      {"Drahtseil", 5, 8, false, 1.0},
    {"Abgrund", 6, 9, false, 1.0},          {"Meister ohne Netz", 7, 11, false, 1.0},
};

// Grid flood fill: can the ball still roll from the start to the goal?
class Reachability {
 public:
  static constexpr double Step = 0.01, Margin = 0.012;
  Reachability(const std::vector<LWall>& walls, const std::vector<LHole>& holes)
      : w_(int(std::lround(BoardW / Step)) + 1), h_(int(std::lround(BoardH / Step)) + 1),
        blocked_(size_t(w_ * h_), 0) {
    const double r2 = Labyrinth::Radius * Labyrinth::Radius;
    for (int j = 0; j < h_; j++) {
      for (int i = 0; i < w_; i++) {
        const double x = i * Step, y = j * Step;
        for (auto& wall : walls) {
          const double cx = std::clamp(x, wall.left, wall.right);
          const double cy = std::clamp(y, wall.top, wall.bottom);
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) < r2) {
            blocked_[size_t(j * w_ + i)] = 1;
            break;
          }
        }
      }
    }
    for (auto& h : holes) {
      for (int c : disk(h)) blocked_[size_t(c)] = 1;
    }
  }

  bool tryAdd(const LHole& hole, double sx, double sy, const LHole& goal) {
    std::vector<int> cells;
    for (int c : disk(hole)) {
      if (!blocked_[size_t(c)]) cells.push_back(c);
    }
    for (int c : cells) blocked_[size_t(c)] = 1;
    if (reachable(sx, sy, goal)) return true;
    for (int c : cells) blocked_[size_t(c)] = 0;
    return false;
  }

 private:
  std::vector<int> disk(const LHole& hole) const {
    const double rr = hole.radius + Margin;
    std::vector<int> cells;
    const int i0 = std::max(0, int(std::floor((hole.x - rr) / Step)));
    const int i1 = std::min(w_ - 1, int(std::ceil((hole.x + rr) / Step)));
    const int j0 = std::max(0, int(std::floor((hole.y - rr) / Step)));
    const int j1 = std::min(h_ - 1, int(std::ceil((hole.y + rr) / Step)));
    for (int j = j0; j <= j1; j++) {
      for (int i = i0; i <= i1; i++) {
        const double dx = i * Step - hole.x, dy = j * Step - hole.y;
        if (dx * dx + dy * dy < rr * rr) cells.push_back(j * w_ + i);
      }
    }
    return cells;
  }

  bool reachable(double sx, double sy, const LHole& goal) const {
    const int s = int(std::lround(sy / Step)) * w_ + int(std::lround(sx / Step));
    if (blocked_[size_t(s)]) return false;
    std::vector<uint8_t> seen(blocked_.size(), 0);
    std::vector<int> queue{s};
    seen[size_t(s)] = 1;
    const double gr2 = goal.radius * goal.radius;
    for (size_t q = 0; q < queue.size(); q++) {
      const int c = queue[q];
      const int i = c % w_, j = c / w_;
      const double dx = i * Step - goal.x, dy = j * Step - goal.y;
      if (dx * dx + dy * dy < gr2) return true;
      const int next[4] = {i > 0 ? c - 1 : -1, i < w_ - 1 ? c + 1 : -1, j > 0 ? c - w_ : -1,
                           j < h_ - 1 ? c + w_ : -1};
      for (int n : next) {
        if (n >= 0 && !seen[size_t(n)] && !blocked_[size_t(n)]) {
          seen[size_t(n)] = 1;
          queue.push_back(n);
        }
      }
    }
    return false;
  }

  int w_, h_;
  std::vector<uint8_t> blocked_;
};

LLevel generateMaze(const std::string& name, int cols, int rows, double holeShare,
                    uint32_t seed, double pathTraps, bool mazeWalls, bool frame) {
  std::mt19937 r(seed);
  std::uniform_real_distribution<double> unit(0, 1);
  const double inner = T;
  const double cw = (BoardW - 2 * inner) / cols, ch = (BoardH - 2 * inner) / rows;
  std::vector<std::vector<bool>> right(cols, std::vector<bool>(rows)),
      down(cols, std::vector<bool>(rows)), visited(cols, std::vector<bool>(rows));
  std::vector<std::vector<std::pair<int, int>>> parent(
      cols, std::vector<std::pair<int, int>>(rows, {-1, -1}));
  std::vector<std::pair<int, int>> stack{{0, 0}};
  visited[0][0] = true;
  while (!stack.empty()) {
    auto [c, row] = stack.back();
    std::vector<std::pair<int, int>> options;
    if (c > 0 && !visited[c - 1][row]) options.push_back({c - 1, row});
    if (c < cols - 1 && !visited[c + 1][row]) options.push_back({c + 1, row});
    if (row > 0 && !visited[c][row - 1]) options.push_back({c, row - 1});
    if (row < rows - 1 && !visited[c][row + 1]) options.push_back({c, row + 1});
    if (options.empty()) {
      stack.pop_back();
      continue;
    }
    auto [nc, nr] = options[std::uniform_int_distribution<size_t>(0, options.size() - 1)(r)];
    if (nc > c) right[c][row] = true;
    if (nc < c) right[nc][row] = true;
    if (nr > row) down[c][row] = true;
    if (nr < row) down[c][nr] = true;
    visited[nc][nr] = true;
    parent[nc][nr] = {c, row};
    stack.push_back({nc, nr});
  }
  // Path from the start to the goal (bottom right cell).
  std::vector<std::pair<int, int>> path{{cols - 1, rows - 1}};
  while (parent[path.back().first][path.back().second].first >= 0) {
    path.push_back(parent[path.back().first][path.back().second]);
  }
  std::set<std::pair<int, int>> onPath(path.begin(), path.end());
  std::reverse(path.begin(), path.end());
  auto cx = [&](int c) { return inner + (c + 0.5) * cw; };
  auto cy = [&](int row) { return inner + (row + 0.5) * ch; };

  LLevel level;
  level.name = name;
  level.frame = frame;
  if (frame) level.walls = frameWalls();
  for (int c = 0; c < cols && mazeWalls; c++) {
    for (int row = 0; row < rows; row++) {
      const double x1 = inner + c * cw, y1 = inner + row * ch;
      if (c < cols - 1 && !right[c][row]) level.walls.push_back(vw(x1 + cw, y1 - T / 2, y1 + ch + T / 2));
      if (row < rows - 1 && !down[c][row]) level.walls.push_back(hw(x1 - T / 2, x1 + cw + T / 2, y1 + ch));
    }
  }
  const double holeRadius = std::min(0.042, std::min(cw, ch) * 0.3);
  for (int c = 0; c < cols; c++) {
    for (int row = 0; row < rows; row++) {
      if (onPath.count({c, row})) continue;
      if (unit(r) < holeShare) {
        level.holes.push_back({cx(c), cy(row), mazeWalls ? holeRadius : std::min(cw, ch) * 0.42});
      }
    }
  }
  level.startX = cx(0);
  level.startY = cy(0);
  level.goal = {cx(cols - 1), cy(rows - 1), holeRadius};
  // Traps on the path itself, only where the ball can still pass.
  Reachability reach(level.walls, level.holes);
  for (size_t i = 2; i + 2 < path.size(); i++) {
    if (unit(r) >= pathTraps) continue;
    auto [x0, y0] = path[i];
    auto [px, py] = path[i - 1];
    auto [nx, ny] = path[i + 1];
    const int d1x = px - x0, d1y = py - y0, d2x = nx - x0, d2y = ny - y0;
    double ox, oy;
    if (d1x == -d2x && d1y == -d2y) {
      const double side = unit(r) < 0.5 ? 1.0 : -1.0;
      ox = d1y != 0 ? side : 0;
      oy = d1x != 0 ? side : 0;
    } else {
      ox = -(d1x + d2x);
      oy = -(d1y + d2y);
    }
    static const double variants[4][2] = {{0.22, 1.0}, {0.27, 0.85}, {0.3, 0.7}, {0.33, 0.55}};
    for (auto& v : variants) {
      LHole trap{cx(x0) + ox * cw * v[0], cy(y0) + oy * ch * v[0], holeRadius * v[1]};
      if (reach.tryAdd(trap, level.startX, level.startY, level.goal)) {
        level.holes.push_back(trap);
        break;
      }
    }
  }
  return level;
}
}  // namespace

int labyrinthLevelCount() {
  return 5 + int(std::size(Mazes)) + 3 + int(std::size(Fields));
}

LLevel labyrinthLevel(int i) {
  static std::vector<std::optional<LLevel>> cache = std::vector<std::optional<LLevel>>(size_t(labyrinthLevelCount()));
  if (cache[size_t(i)]) return *cache[size_t(i)];
  LLevel l;
  const int mazes = int(std::size(Mazes));
  if (i < 5) {
    l = handmade()[size_t(i)];
  } else if (i < 5 + mazes) {
    const auto& m = Mazes[i - 5];
    l = generateMaze(m.name, m.cols, m.rows, m.holeShare, uint32_t(1000 + (i - 5) * 37),
                     m.pathTraps, true, true);
  } else if (i < 5 + mazes + 3) {
    l = edgeLevels()[size_t(i - 5 - mazes)];
  } else {
    const auto& f = Fields[i - 8 - mazes];
    l = generateMaze(f.name, f.cols, f.rows, 1.0, uint32_t(5000 + (i - 8 - mazes) * 53),
                     f.pathTraps, false, f.frame);
  }
  cache[size_t(i)] = l;
  return l;
}

Labyrinth::Labyrinth(LLevel l) : level(std::move(l)) { reset(); }

void Labyrinth::reset() {
  x = level.startX;
  y = level.startY;
  vx = vy = 0;
  elapsed = 0;
  state = BallState::Rolling;
}

void Labyrinth::step(double dt, double tiltX, double tiltY) {
  if (state != BallState::Rolling) return;
  elapsed += dt;
  const int steps = std::max(1, int(std::ceil(dt / 0.004)));
  const double h = dt / steps;
  for (int i = 0; i < steps && state == BallState::Rolling; i++) {
    vx += std::clamp(tiltX, -1.0, 1.0) * Gravity * h;
    vy += std::clamp(tiltY, -1.0, 1.0) * Gravity * h;
    const double f = std::pow(1 - damping, h);
    vx *= f;
    vy *= f;
    x += vx * h;
    y += vy * h;
    for (auto& w : level.walls) collide(w);
    checkHoles();
    if (state == BallState::Rolling && (x < 0 || y < 0 || x > BoardW || y > BoardH)) {
      state = BallState::Fell;
      x = std::clamp(x, 0.0, BoardW);
      y = std::clamp(y, 0.0, BoardH);
    }
  }
}

void Labyrinth::collide(const LWall& w) {
  const double cx = std::clamp(x, w.left, w.right), cy = std::clamp(y, w.top, w.bottom);
  const double dx = x - cx, dy = y - cy;
  const double d2 = dx * dx + dy * dy;
  if (d2 >= Radius * Radius) return;
  if (d2 == 0) {
    // Centre inside the wall: push out on the nearest side.
    const double pushes[4] = {x - w.left, w.right - x, y - w.top, w.bottom - y};
    const double m = *std::min_element(pushes, pushes + 4);
    if (m == pushes[0]) {
      x = w.left - Radius;
      vx = -std::abs(vx) * restitution;
    } else if (m == pushes[1]) {
      x = w.right + Radius;
      vx = std::abs(vx) * restitution;
    } else if (m == pushes[2]) {
      y = w.top - Radius;
      vy = -std::abs(vy) * restitution;
    } else {
      y = w.bottom + Radius;
      vy = std::abs(vy) * restitution;
    }
    return;
  }
  const double d = std::sqrt(d2);
  const double nx = dx / d, ny = dy / d;
  x = cx + nx * Radius;
  y = cy + ny * Radius;
  const double vn = vx * nx + vy * ny;
  if (vn < 0) {
    vx -= (1 + restitution) * vn * nx;
    vy -= (1 + restitution) * vn * ny;
  }
}

void Labyrinth::checkHoles() {
  auto inside = [&](const LHole& h) {
    const double dx = x - h.x, dy = y - h.y;
    return dx * dx + dy * dy < h.radius * h.radius;
  };
  if (inside(level.goal)) {
    state = BallState::Won;
    x = level.goal.x;
    y = level.goal.y;
    return;
  }
  for (auto& h : level.holes) {
    if (inside(h)) {
      state = BallState::Fell;
      x = h.x;
      y = h.y;
      return;
    }
  }
}

// ---------------------------------------------------------------------- Darts

const int dartboard::Numbers[20] = {20, 1, 18, 4, 13, 6, 10, 15, 2, 17,
                                    3, 19, 7, 16, 8, 11, 14, 9, 12, 5};

DartHit dartboard::score(double x, double y) {
  const double r = std::sqrt(x * x + y * y);
  if (r > DoubleOuter) return {0, 0};
  if (r <= BullInner) return {25, 2};
  if (r <= BullOuter) return {25, 1};
  const double deg = std::fmod(std::atan2(x, -y) * 180 / 3.14159265358979323846 + 360, 360);
  const int segment = Numbers[int(std::fmod(deg + 9, 360) / 18)];
  const int mult = (r >= TripleInner && r <= TripleOuter) ? 3 : r >= DoubleInner ? 2 : 1;
  return {segment, mult};
}

std::string DartHit::label() const {
  if (miss()) return "Daneben";
  if (value == 25) return multiplier == 2 ? "Bull" : "25";
  static const char* prefix[] = {"", "S", "D", "T"};
  return prefix[multiplier] + std::to_string(value);
}

static const int ClockTargets[21] = {1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11,
                                     12, 13, 14, 15, 16, 17, 18, 19, 20, 25};

Darts::Darts(int p, DartsMode m, bool d) : players(p), mode(m), doubleOut(d), states(p) {
  for (auto& s : states) s.remaining = m == DartsMode::X501 ? 501 : m == DartsMode::X301 ? 301 : 0;
}

int Darts::target(int player) const {
  return ClockTargets[std::min(states[player].remaining, 20)];
}

void Darts::throwDart(const DartHit& hit) {
  if (isOver()) return;
  DartsPlayer& s = states[current];
  if (turn.empty()) {
    turnStart_ = s.remaining;
    lastBust = false;
  }
  turn.push_back(hit);
  s.darts++;
  if (mode == DartsMode::Clock) {
    if (!hit.miss() && hit.value == target(current)) {
      s.remaining++;
      if (s.remaining >= 21) {
        winner = current;
        return;
      }
    }
  } else {
    const int left = s.remaining - hit.points();
    const bool bust =
        left < 0 || (doubleOut && (left == 1 || (left == 0 && hit.multiplier != 2)));
    if (bust) {
      s.scored -= turnStart_ - s.remaining;
      s.remaining = turnStart_;
      lastBust = true;
      next();
      return;
    }
    s.remaining = left;
    s.scored += hit.points();
    if (left == 0) {
      winner = current;
      return;
    }
  }
  if (turn.size() == 3) next();
}

void Darts::next() {
  turn.clear();
  current = (current + 1) % players;
  if (current == 0) round++;
}

// -------------------------------------------------------------------- Billard

const double Billiard::Pockets[6][2] = {{0, 0}, {W / 2, -0.01}, {W, 0},
                                        {0, H}, {W / 2, H + 0.01}, {W, H}};

Billiard::Billiard() {
  balls.push_back({0, W * 0.25, H / 2});
  static const int order[15] = {1, 9, 2, 10, 8, 3, 11, 7, 14, 4, 5, 13, 15, 6, 12};
  int i = 0;
  const double d = Radius * 2 + 0.002;
  for (int row = 0; row < 5; row++) {
    for (int k = 0; k <= row; k++) {
      balls.push_back({order[i++], W * 0.7 + row * d * std::sqrt(3.0) / 2, H / 2 + (k - row / 2.0) * d});
    }
  }
}

bool Billiard::moving() const {
  for (auto& b : balls) {
    if (!b.pocketed && b.moving()) return true;
  }
  return false;
}

int Billiard::remaining() const {
  int n = 0;
  for (auto& b : balls) n += b.number != 0 && !b.pocketed;
  return n;
}

bool Billiard::shoot(double angle, double power, double spin) {
  if (moving() || cue().pocketed || won()) return false;
  cueInHand = false;
  const double speed = std::clamp(power, 0.0, 1.0) * MaxSpeed;
  dirX_ = std::cos(angle);
  dirY_ = std::sin(angle);
  spin_ = std::clamp(spin, -1.0, 1.0);
  cue().vx = dirX_ * speed;
  cue().vy = dirY_ * speed;
  shots++;
  pocketedThisShot.clear();
  firstHit = -1;
  scratched = false;
  return true;
}

void Billiard::step(double dt) {
  const int steps = std::max(1, int(std::ceil(dt / 0.002)));
  for (int s = 0; s < steps; s++) substep(dt / steps);
  if (!moving() && cue().pocketed) respawnCue();
}

void Billiard::substep(double h) {
  for (auto& b : balls) {
    if (b.pocketed) continue;
    const double v = std::sqrt(b.vx * b.vx + b.vy * b.vy);
    if (v > 0) {
      const double nv = std::max(0.0, v - Friction * h);
      if (nv < 0.005) {
        b.vx = b.vy = 0;
      } else {
        b.vx *= nv / v;
        b.vy *= nv / v;
      }
    }
    b.x += b.vx * h;
    b.y += b.vy * h;
    if (b.number == 0 && spin_ != 0) spin_ *= std::exp(-0.35 * std::sqrt(b.vx * b.vx + b.vy * b.vy) * h);
  }
  for (size_t i = 0; i < balls.size(); i++) {
    if (balls[i].pocketed) continue;
    for (size_t j = i + 1; j < balls.size(); j++) {
      if (!balls[j].pocketed) collide(balls[i], balls[j]);
    }
  }
  for (auto& b : balls) {
    if (b.pocketed) continue;
    for (auto& p : Pockets) {
      const double dx = b.x - p[0], dy = b.y - p[1];
      if (dx * dx + dy * dy < PocketRadius * PocketRadius) {
        b.pocketed = true;
        b.vx = b.vy = 0;
        if (b.number == 0) {
          fouls++;
          scratched = true;
        } else {
          pocketedThisShot.push_back(b.number);
        }
        break;
      }
    }
    if (b.pocketed) continue;
    if (b.x < Radius) {
      b.x = Radius;
      b.vx = std::abs(b.vx) * Cushion;
    } else if (b.x > W - Radius) {
      b.x = W - Radius;
      b.vx = -std::abs(b.vx) * Cushion;
    }
    if (b.y < Radius) {
      b.y = Radius;
      b.vy = std::abs(b.vy) * Cushion;
    } else if (b.y > H - Radius) {
      b.y = H - Radius;
      b.vy = -std::abs(b.vy) * Cushion;
    }
  }
}

void Billiard::collide(PoolBall& a, PoolBall& b) {
  const double dx = b.x - a.x, dy = b.y - a.y;
  const double d2 = dx * dx + dy * dy;
  const double minD = Radius * 2;
  if (d2 >= minD * minD || d2 == 0) return;
  if (firstHit < 0) {
    if (a.number == 0) firstHit = b.number;
    if (b.number == 0) firstHit = a.number;
  }
  const double d = std::sqrt(d2);
  const double nx = dx / d, ny = dy / d;
  const double overlap = (minD - d) / 2;
  a.x -= nx * overlap;
  a.y -= ny * overlap;
  b.x += nx * overlap;
  b.y += ny * overlap;
  const double rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
  if (rel <= 0) return;
  const double impulse = rel * (1 + 0.95) / 2;
  PoolBall* cueBall = a.number == 0 ? &a : b.number == 0 ? &b : nullptr;
  const double cueSpeed = cueBall ? std::sqrt(cueBall->vx * cueBall->vx + cueBall->vy * cueBall->vy) : 0;
  a.vx -= impulse * nx;
  a.vy -= impulse * ny;
  b.vx += impulse * nx;
  b.vy += impulse * ny;
  // Follow (top spin) or draw (back spin) after the first contact.
  if (cueBall && spin_ != 0) {
    const double k = spin_ * 0.6 * cueSpeed;
    cueBall->vx += dirX_ * k;
    cueBall->vy += dirY_ * k;
    spin_ = 0;
  }
}

void Billiard::respawnCue() {
  double x = W * 0.25;
  const double y = H / 2;
  auto blocked = [&](double px) {
    for (size_t i = 1; i < balls.size(); i++) {
      const auto& b = balls[i];
      if (!b.pocketed && std::pow(b.x - px, 2) + std::pow(b.y - y, 2) < std::pow(Radius * 2.2, 2)) {
        return true;
      }
    }
    return false;
  };
  while (blocked(x) && x > Radius * 2) x -= Radius;
  PoolBall& c = cue();
  c.pocketed = false;
  c.x = x;
  c.y = y;
  c.vx = c.vy = 0;
  cueInHand = true;
}

bool Billiard::placeCue(double x, double y) {
  if (!cueInHand || moving()) return false;
  const double px = std::clamp(x, Radius, W - Radius), py = std::clamp(y, Radius, H - Radius);
  for (size_t i = 1; i < balls.size(); i++) {
    const auto& b = balls[i];
    if (!b.pocketed && std::pow(b.x - px, 2) + std::pow(b.y - py, 2) < std::pow(Radius * 2.05, 2)) {
      return false;
    }
  }
  cue().x = px;
  cue().y = py;
  return true;
}

Billiard::Preview Billiard::preview(double angle) const {
  const double dx = std::cos(angle), dy = std::sin(angle);
  const PoolBall& c = cue();
  double best = 1e18;
  int hit = -1;
  for (size_t i = 1; i < balls.size(); i++) {
    const auto& b = balls[i];
    if (b.pocketed) continue;
    const double ox = b.x - c.x, oy = b.y - c.y;
    const double along = ox * dx + oy * dy;
    if (along <= 0) continue;
    const double perp2 = ox * ox + oy * oy - along * along;
    const double r2 = 4 * Radius * Radius;
    if (perp2 > r2) continue;
    const double t = along - std::sqrt(r2 - perp2);
    if (t < best) {
      best = t;
      hit = int(i);
    }
  }
  double wall = 1e18;
  if (dx > 0) wall = std::min(wall, (W - Radius - c.x) / dx);
  if (dx < 0) wall = std::min(wall, (Radius - c.x) / dx);
  if (dy > 0) wall = std::min(wall, (H - Radius - c.y) / dy);
  if (dy < 0) wall = std::min(wall, (Radius - c.y) / dy);
  if (hit >= 0 && best <= wall) {
    const double gx = c.x + dx * best, gy = c.y + dy * best;
    const double nx = balls[size_t(hit)].x - gx, ny = balls[size_t(hit)].y - gy;
    const double len = std::sqrt(nx * nx + ny * ny);
    return {gx, gy, hit, nx / len, ny / len};
  }
  const double t = wall < 1e17 ? std::max(0.0, wall) : 0.0;
  return {c.x + dx * t, c.y + dy * t, -1, 0, 0};
}

Group groupOf(int n) {
  if (n >= 1 && n <= 7) return Group::Solids;
  if (n >= 9 && n <= 15) return Group::Stripes;
  return Group::None;
}

int EightBall::remainingOf(const Billiard& g, int player) const {
  if (groups[player] == Group::None) return 7;
  int n = 0;
  for (auto& b : g.balls) n += !b.pocketed && groupOf(b.number) == groups[player];
  return n;
}

void EightBall::evaluate(const std::vector<int>& pocketed, int firstHit, bool scratched,
                         bool clearedBefore) {
  if (winner >= 0) return;
  const int me = current, opp = 1 - current;
  const Group mine = groups[me];
  const bool foul = scratched || firstHit < 0 || (mine == Group::None && firstHit == 8) ||
                    (mine != Group::None &&
                     !(groupOf(firstHit) == mine || (clearedBefore && firstHit == 8)));
  if (std::find(pocketed.begin(), pocketed.end(), 8) != pocketed.end()) {
    if (clearedBefore && !foul) {
      winner = me;
      lastEvent = "Die 8 versenkt – Sieg!";
    } else {
      winner = opp;
      lastEvent = "Die 8 zu früh oder mit Foul versenkt – verloren!";
    }
    return;
  }
  if (mine == Group::None && !foul) {
    for (int n : pocketed) {
      if (groupOf(n) != Group::None) {
        groups[me] = groupOf(n);
        groups[opp] = groups[me] == Group::Solids ? Group::Stripes : Group::Solids;
        break;
      }
    }
  }
  const Group own = groups[me];
  bool pottedOwn = false;
  for (int n : pocketed) pottedOwn |= own != Group::None && groupOf(n) == own;
  if (foul) {
    lastEvent = scratched ? "Foul: weiße Kugel versenkt"
                : firstHit < 0 ? "Foul: keine Kugel getroffen"
                               : "Foul: falsche Kugel zuerst getroffen";
    current = opp;
  } else if (pottedOwn) {
    lastEvent = "Versenkt – nochmal!";
  } else {
    lastEvent = pocketed.empty() ? "Nichts versenkt" : "Fremde Kugel versenkt";
    current = opp;
  }
}

int SoloRules::target(const Billiard& g) const {
  if (mode != SoloMode::Rotation) return -1;
  int best = -1;
  for (auto& b : g.balls) {
    if (b.number != 0 && !b.pocketed && (best < 0 || b.number < best)) best = b.number;
  }
  return best;
}

int SoloRules::othersLeft(const Billiard& g) {
  int n = 0;
  for (auto& b : g.balls) n += b.number != 0 && b.number != 8 && !b.pocketed;
  return n;
}

void SoloRules::evaluate(const std::vector<int>& pocketed, int firstHit, bool scratched,
                         int othersBefore, int targetBefore) {
  if (lost) return;
  std::vector<std::string> events;
  if (mode == SoloMode::EightLast &&
      std::find(pocketed.begin(), pocketed.end(), 8) != pocketed.end() &&
      (othersBefore > 0 || scratched)) {
    lost = true;
    lastEvent = othersBefore > 0 ? "Die 8 zu früh versenkt – verloren!"
                                 : "Die 8 mit Foul versenkt – verloren!";
    return;
  }
  if (scratched) events.push_back("Foul: weiße Kugel versenkt");
  if (firstHit < 0) {
    penalties++;
    events.push_back("Foul: keine Kugel getroffen");
  } else if (mode == SoloMode::Rotation && targetBefore >= 0 && firstHit != targetBefore) {
    penalties++;
    events.push_back("Foul: zuerst die " + std::to_string(targetBefore) + " treffen");
  } else if (mode == SoloMode::EightLast && firstHit == 8 && othersBefore > 0) {
    penalties++;
    events.push_back("Foul: die 8 erst zum Schluss anspielen");
  }
  if (events.empty()) {
    if (pocketed.empty()) {
      lastEvent.clear();
    } else {
      lastEvent = "Versenkt: ";
      for (size_t i = 0; i < pocketed.size(); i++) {
        lastEvent += (i ? ", " : "") + std::to_string(pocketed[i]);
      }
    }
  } else {
    lastEvent.clear();
    for (size_t i = 0; i < events.size(); i++) lastEvent += (i ? " • " : "") + events[i];
  }
}
