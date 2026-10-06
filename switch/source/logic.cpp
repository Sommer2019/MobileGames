#include "logic.hpp"

#include <algorithm>
#include <climits>
#include <cmath>
#include <cstdlib>

// ------------------------------------------------------------------ 4 gewinnt

ConnectFour::ConnectFour(int p) : players(std::clamp(p, 2, 4)) {
  static const int cols[] = {7, 7, 9, 10};
  static const int rws[] = {6, 6, 7, 8};
  columns = cols[players - 1];
  rows = rws[players - 1];
  board.assign(rows, std::vector<int>(columns, 0));
}

bool ConnectFour::canDrop(int col) const {
  return !isOver() && col >= 0 && col < columns && board[0][col] == 0;
}

int ConnectFour::drop(int col) {
  if (!canDrop(col)) return -1;
  int row = rows - 1;
  while (board[row][col] != 0) row--;
  board[row][col] = current;
  std::vector<Cell> line;
  if (findLine(row, col, &line)) {
    winner = current;
    winningCells = line;
  } else if (std::all_of(board[0].begin(), board[0].end(),
                         [](int v) { return v != 0; })) {
    draw = true;
  } else {
    current = current % players + 1;
  }
  return row;
}

bool ConnectFour::findLine(int row, int col, std::vector<Cell>* out) const {
  const int p = board[row][col];
  static const int dirs[4][2] = {{0, 1}, {1, 0}, {1, 1}, {1, -1}};
  for (auto& d : dirs) {
    std::vector<Cell> cells{{row, col}};
    for (int sign : {1, -1}) {
      int r = row + d[0] * sign, c = col + d[1] * sign;
      while (r >= 0 && r < rows && c >= 0 && c < columns && board[r][c] == p) {
        cells.push_back({r, c});
        r += d[0] * sign;
        c += d[1] * sign;
      }
    }
    if (cells.size() >= 4) {
      if (out) *out = cells;
      return true;
    }
  }
  return false;
}

std::vector<int> ConnectFour::order() const {
  std::vector<int> cols(columns);
  for (int c = 0; c < columns; c++) cols[c] = c;
  const int center = columns / 2;
  std::stable_sort(cols.begin(), cols.end(), [center](int a, int b) {
    return std::abs(a - center) < std::abs(b - center);
  });
  return cols;
}

int ConnectFour::aiMove(int depth) const {
  const int me = current;
  int bestScore = INT_MIN, best = -1;
  for (int col : order()) {
    if (!canDrop(col)) continue;
    ConnectFour g = *this;
    g.drop(col);
    const int score = g.minimax(depth - 1, INT_MIN / 2, INT_MAX / 2, me);
    if (score > bestScore) {
      bestScore = score;
      best = col;
    }
  }
  return best;
}

int ConnectFour::minimax(int depth, int alpha, int beta, int me) const {
  if (winner != 0) return winner == me ? 100000 + depth : -100000 - depth;
  if (draw) return 0;
  if (depth == 0) return evaluate(me);
  const bool maximizing = current == me;
  int value = maximizing ? INT_MIN / 2 : INT_MAX / 2;
  for (int col : order()) {
    if (!canDrop(col)) continue;
    ConnectFour child = *this;
    child.drop(col);
    const int score = child.minimax(depth - 1, alpha, beta, me);
    if (maximizing) {
      value = std::max(value, score);
      alpha = std::max(alpha, value);
    } else {
      value = std::min(value, score);
      beta = std::min(beta, value);
    }
    if (alpha >= beta) break;
  }
  return value;
}

int ConnectFour::evaluate(int me) const {
  int score = 0;
  const int center = columns / 2;
  for (int r = 0; r < rows; r++) {
    if (board[r][center] == me) score += 3;
  }
  static const int dirs[4][2] = {{0, 1}, {1, 0}, {1, 1}, {1, -1}};
  static const int mineScore[] = {0, 1, 5, 50, 0};
  static const int theirScore[] = {0, 1, 6, 60, 0};
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < columns; c++) {
      for (auto& d : dirs) {
        const int er = r + d[0] * 3, ec = c + d[1] * 3;
        if (er < 0 || er >= rows || ec < 0 || ec >= columns) continue;
        int mine = 0, theirs = 0;
        for (int i = 0; i < 4; i++) {
          const int v = board[r + d[0] * i][c + d[1] * i];
          if (v == me) {
            mine++;
          } else if (v != 0) {
            theirs++;
          }
        }
        if (theirs == 0) score += mineScore[mine];
        if (mine == 0) score -= theirScore[theirs];
      }
    }
  }
  return score;
}

// ----------------------------------------------------------------------- Dame

Checkers::Checkers() {
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if ((r + c) % 2 == 1) {
        if (r < 3) board[r][c] = {true, Side::Black, false};
        if (r > 4) board[r][c] = {true, Side::White, false};
      }
    }
  }
}

std::vector<CheckersMove> Checkers::legalMoves() const {
  std::vector<CheckersMove> caps, quietMoves_;
  if (isOver()) return caps;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      const Piece& p = board[r][c];
      if (!p.present || p.side != turn) continue;
      std::vector<Cell> path{{r, c}};
      std::vector<Cell> taken;
      captures(r, c, p, path, taken, caps);
      if (caps.empty()) quiet(r, c, p, quietMoves_);
    }
  }
  return caps.empty() ? quietMoves_ : caps;
}

void Checkers::quiet(int r, int c, const Piece& p,
                     std::vector<CheckersMove>& out) const {
  static const int dirs[4][2] = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
  for (auto& d : dirs) {
    if (!p.king && d[0] != forward(p.side)) continue;
    int nr = r + d[0], nc = c + d[1];
    while (inside(nr, nc) && !board[nr][nc].present) {
      out.push_back({{{r, c}, {nr, nc}}, {}});
      if (!p.king) break;
      nr += d[0];
      nc += d[1];
    }
  }
}

void Checkers::captures(int r, int c, const Piece& p, std::vector<Cell>& path,
                        std::vector<Cell>& taken,
                        std::vector<CheckersMove>& out) const {
  const Cell start = path.front();
  auto empty = [&](int rr, int cc) {
    return !board[rr][cc].present || Cell{rr, cc} == start;
  };
  static const int dirs[4][2] = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
  for (auto& d : dirs) {
    if (!p.king && d[0] != forward(p.side)) continue;
    int nr = r + d[0], nc = c + d[1];
    if (p.king) {
      while (inside(nr, nc) && empty(nr, nc)) {
        nr += d[0];
        nc += d[1];
      }
    }
    if (!inside(nr, nc)) continue;
    const Piece& victim = board[nr][nc];
    if (!victim.present || Cell{nr, nc} == start || victim.side == p.side ||
        std::find(taken.begin(), taken.end(), Cell{nr, nc}) != taken.end()) {
      continue;
    }
    int lr = nr + d[0], lc = nc + d[1];
    while (inside(lr, lc) && empty(lr, lc)) {
      path.push_back({lr, lc});
      taken.push_back({nr, nc});
      const bool promotes = !p.king && lr == (p.side == Side::White ? 0 : 7);
      if (promotes) {
        // Reaching the far row ends the move.
        out.push_back({path, taken});
      } else {
        const size_t before = out.size();
        captures(lr, lc, p, path, taken, out);
        if (out.size() == before) out.push_back({path, taken});
      }
      path.pop_back();
      taken.pop_back();
      if (!p.king) break;
      lr += d[0];
      lc += d[1];
    }
  }
}

void Checkers::apply(const CheckersMove& m) {
  auto [fr, fc] = m.from();
  auto [tr, tc] = m.to();
  Piece p = board[fr][fc];
  const bool movedKing = p.king;
  board[fr][fc] = {};
  for (auto [cr, cc] : m.captured) board[cr][cc] = {};
  if (!p.king && tr == (p.side == Side::White ? 0 : 7)) p.king = true;
  board[tr][tc] = p;
  quietMoves = (!m.captured.empty() || !movedKing) ? 0 : quietMoves + 1;
  lastPath = m.path;
  turn = turn == Side::White ? Side::Black : Side::White;
  if (legalMoves().empty()) {
    hasWinner = true;
    winner = turn == Side::White ? Side::Black : Side::White;
  } else if (quietMoves >= 50) {
    draw = true;
  }
}

CheckersMove Checkers::aiMove(std::mt19937& rng) const {
  const auto moves = legalMoves();
  std::uniform_real_distribution<double> noise(0, 1);
  double best = -1e9;
  CheckersMove choice = moves.front();
  for (const auto& m : moves) {
    Checkers g = *this;
    g.apply(m);
    double score = m.captured.size() * 10.0;
    if (g.hasWinner && g.winner == turn) score += 1000;
    size_t threat = 0;
    for (const auto& reply : g.legalMoves()) {
      threat = std::max(threat, reply.captured.size());
    }
    score -= threat * 9.0;
    const auto [fr, fc] = m.from();
    const auto [tr, tc] = m.to();
    if (!board[fr][fc].king) {
      score += (turn == Side::White ? 7 - tr : tr) * 0.3;
      if (g.board[tr][tc].king) score += 8;
    }
    score += noise(rng);
    if (score > best) {
      best = score;
      choice = m;
    }
  }
  return choice;
}

namespace {
// Material (kings count more) plus a little for advanced men.
double checkersEval(const Checkers& g, Side me) {
  double score = 0;
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      const Piece& p = g.board[r][c];
      if (!p.present) continue;
      double v = p.king ? 1.7 : 1.0;
      if (!p.king) v += (p.side == Side::White ? 7 - r : r) * 0.04;
      score += p.side == me ? v : -v;
    }
  }
  return score;
}

double checkersSearch(const Checkers& g, int depth, double alpha, double beta, Side me) {
  if (g.hasWinner) return g.winner == me ? 1000.0 + depth : -1000.0 - depth;
  if (g.draw) return 0;
  if (depth == 0) return checkersEval(g, me);
  const auto moves = g.legalMoves();
  if (moves.empty()) return g.turn == me ? -1000.0 : 1000.0;
  const bool maximizing = g.turn == me;
  double v = maximizing ? -1e18 : 1e18;
  for (auto& m : moves) {
    Checkers c = g;
    c.apply(m);
    const double s = checkersSearch(c, depth - 1, alpha, beta, me);
    if (maximizing) {
      v = std::max(v, s);
      alpha = std::max(alpha, v);
    } else {
      v = std::min(v, s);
      beta = std::min(beta, v);
    }
    if (alpha >= beta) break;
  }
  return v;
}
}  // namespace

CheckersMove Checkers::strongMove(std::mt19937& rng) const {
  const auto moves = legalMoves();
  std::uniform_real_distribution<double> noise(0, 0.01);
  double best = -1e18;
  CheckersMove choice = moves.front();
  for (const auto& m : moves) {
    Checkers g = *this;
    g.apply(m);
    const double s = checkersSearch(g, 3, -1e18, 1e18, turn) + noise(rng);
    if (s > best) {
      best = s;
      choice = m;
    }
  }
  return choice;
}

// ---------------------------------------------------------------------- Snake

Snake::Snake(int w, int h, bool wr, uint32_t seed)
    : width(w), height(h), wrap(wr), rng_(seed) {
  const int x = w / 2, y = h / 2;
  for (int i = 0; i < 3; i++) body.push_back({x, y + i});
  placeFood();
}

double Snake::speed() const { return std::min(16.0, 6 + score * 0.25); }

static bool opposite(Dir a, Dir b) {
  return (a == Dir::Up && b == Dir::Down) || (a == Dir::Down && b == Dir::Up) ||
         (a == Dir::Left && b == Dir::Right) ||
         (a == Dir::Right && b == Dir::Left);
}

void Snake::turn(Dir d) {
  const Dir base = queue_.empty() ? direction : queue_.back();
  if (d == base || opposite(d, base) || queue_.size() >= 3) return;
  queue_.push_back(d);
}

void Snake::placeFood() {
  std::vector<Cell> free;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if (std::find(body.begin(), body.end(), Cell{x, y}) == body.end()) {
        free.push_back({x, y});
      }
    }
  }
  if (free.empty()) return;
  std::uniform_int_distribution<size_t> pick(0, free.size() - 1);
  food = free[pick(rng_)];
}

void Snake::step() {
  if (dead || won()) return;
  if (!queue_.empty()) {
    direction = queue_.front();
    queue_.erase(queue_.begin());
  }
  auto [x, y] = body.front();
  switch (direction) {
    case Dir::Up: y--; break;
    case Dir::Down: y++; break;
    case Dir::Left: x--; break;
    case Dir::Right: x++; break;
  }
  if (wrap) {
    x = (x + width) % width;
    y = (y + height) % height;
  } else if (x < 0 || y < 0 || x >= width || y >= height) {
    dead = true;
    return;
  }
  const bool eats = Cell{x, y} == food;
  // The tail moves away this step unless the snake grows.
  const auto end = eats ? body.end() : body.end() - 1;
  if (std::find(body.begin(), end, Cell{x, y}) != end) {
    dead = true;
    return;
  }
  body.push_front({x, y});
  if (eats) {
    score++;
    placeFood();
  } else {
    body.pop_back();
  }
}

// ------------------------------------------------------------------ Schütteln

bool ShakeDetector::add(double x, double y, double z, double time) {
  // Gravity changes slowly, shaking fast: a low-pass filter separates them.
  if (!hasGravity_) {
    gx_ = x;
    gy_ = y;
    gz_ = z;
    hasGravity_ = true;
    return false;
  }
  gx_ += (x - gx_) * 0.1;
  gy_ += (y - gy_) * 0.1;
  gz_ += (z - gz_) * 0.1;
  const double lx = x - gx_, ly = y - gy_, lz = z - gz_;
  if (std::sqrt(lx * lx + ly * ly + lz * lz) < Threshold) return false;
  if (time - lastShake_ < Cooldown) return false;
  peaks_.push_back(time);
  peaks_.erase(std::remove_if(peaks_.begin(), peaks_.end(),
                              [&](double t) { return time - t > Window; }),
               peaks_.end());
  if ((int)peaks_.size() >= MinPeaks) {
    peaks_.clear();
    lastShake_ = time;
    return true;
  }
  return false;
}

// ----------------------------------------------------------------- Würfel

int DiceCup::sum() const {
  int s = 0;
  for (int i = 0; i < count; i++) s += values[i];
  return s;
}

void DiceCup::roll(std::mt19937& rng) {
  std::uniform_int_distribution<int> die(1, 6);
  for (int i = 0; i < count; i++) {
    if (!held[i]) values[i] = die(rng);
  }
  history.push_front(std::vector<int>(values.begin(), values.begin() + count));
  while (history.size() > 10) history.pop_back();
}
