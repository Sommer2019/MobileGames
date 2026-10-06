#include "logic2.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>

// ---------------------------------------------------------------------- Mühle

Mill::Mill() { board.fill(0); }

const std::vector<std::vector<int>>& Mill::neighbours() {
  static const std::vector<std::vector<int>> n = [] {
    std::vector<std::vector<int>> v(24);
    auto link = [&](int a, int b) {
      v[a].push_back(b);
      v[b].push_back(a);
    };
    for (int ring = 0; ring < 3; ring++) {
      for (int i = 0; i < 8; i++) link(ring * 8 + i, ring * 8 + (i + 1) % 8);
    }
    for (int k : {1, 3, 5, 7}) {
      link(k, k + 8);
      link(k + 8, k + 16);
    }
    return v;
  }();
  return n;
}

const std::vector<std::array<int, 3>>& Mill::mills() {
  static const std::vector<std::array<int, 3>> m = [] {
    std::vector<std::array<int, 3>> v;
    for (int ring = 0; ring < 3; ring++) {
      for (int s : {0, 2, 4, 6}) {
        v.push_back({ring * 8 + s, ring * 8 + s + 1, ring * 8 + (s + 2) % 8});
      }
    }
    for (int k : {1, 3, 5, 7}) v.push_back({k, k + 8, k + 16});
    return v;
  }();
  return m;
}

int Mill::stones(int p) const { return int(std::count(board.begin(), board.end(), p)); }

bool Mill::inMill(int point) const {
  const int p = board[point];
  if (p == 0) return false;
  for (auto& m : mills()) {
    if (std::find(m.begin(), m.end(), point) == m.end()) continue;
    if (board[m[0]] == p && board[m[1]] == p && board[m[2]] == p) return true;
  }
  return false;
}

bool Mill::closesMill(int point, int player) const {
  for (auto& m : mills()) {
    if (std::find(m.begin(), m.end(), point) == m.end()) continue;
    bool all = true;
    for (int x : m) all &= x == point || board[x] == player;
    if (all) return true;
  }
  return false;
}

std::vector<int> Mill::removable() const {
  const int opp = 3 - turn;
  std::vector<int> all, free;
  for (int i = 0; i < 24; i++) {
    if (board[i] != opp) continue;
    all.push_back(i);
    if (!inMill(i)) free.push_back(i);
  }
  return free.empty() ? all : free;
}

bool Mill::canPlace(int point) const {
  return !isOver() && !mustRemove && placing(turn) && board[point] == 0;
}

std::vector<int> Mill::targets(int from) const {
  std::vector<int> out;
  if (isOver() || mustRemove || placing(turn) || board[from] != turn) return out;
  if (canFly(turn)) {
    for (int i = 0; i < 24; i++) {
      if (board[i] == 0) out.push_back(i);
    }
    return out;
  }
  for (int n : neighbours()[from]) {
    if (board[n] == 0) out.push_back(n);
  }
  return out;
}

bool Mill::place(int point) {
  if (!canPlace(point)) return false;
  board[point] = turn;
  toPlace[turn]--;
  lastFrom = lastTo = point;
  afterAction(point);
  return true;
}

bool Mill::move(int from, int to) {
  auto t = targets(from);
  if (std::find(t.begin(), t.end(), to) == t.end()) return false;
  board[from] = 0;
  board[to] = turn;
  lastFrom = from;
  lastTo = to;
  quietMoves++;
  afterAction(to);
  return true;
}

bool Mill::remove(int point) {
  if (!mustRemove) return false;
  auto r = removable();
  if (std::find(r.begin(), r.end(), point) == r.end()) return false;
  board[point] = 0;
  mustRemove = false;
  quietMoves = 0;
  endTurn();
  return true;
}

void Mill::afterAction(int point) {
  if (inMill(point) && !removable().empty()) {
    mustRemove = true;
    return;
  }
  endTurn();
}

void Mill::endTurn() {
  const int opp = 3 - turn;
  turn = opp;
  if (!placing(opp) && stones(opp) + toPlace[opp] < 3) {
    winner = 3 - opp;
  } else if (!hasMove(opp)) {
    winner = 3 - opp;
  } else if (quietMoves >= 100) {
    draw = true;
  }
}

bool Mill::hasMove(int p) const {
  if (placing(p) || canFly(p)) return true;
  for (int i = 0; i < 24; i++) {
    if (board[i] != p) continue;
    for (int n : neighbours()[i]) {
      if (board[n] == 0) return true;
    }
  }
  return false;
}

int Mill::threat(int point, int player) const {
  int best = 0;
  for (auto& m : mills()) {
    if (std::find(m.begin(), m.end(), point) == m.end()) continue;
    int n = 0;
    for (int x : m) n += board[x] == player;
    best = std::max(best, n);
  }
  return best;
}

std::optional<Mill::Action> Mill::aiAction(std::mt19937& rng) const {
  if (isOver()) return std::nullopt;
  const int me = turn, opp = 3 - turn;
  auto pick = [&](const std::vector<int>& v) {
    return v[std::uniform_int_distribution<size_t>(0, v.size() - 1)(rng)];
  };
  if (mustRemove) {
    auto options = removable();
    int best = 0;
    for (int x : options) best = std::max(best, threat(x, opp));
    std::vector<int> top;
    for (int x : options) {
      if (threat(x, opp) == best) top.push_back(x);
    }
    return Action{Action::Remove, pick(top), -1};
  }
  if (placing(me)) {
    std::vector<int> empty, win, block, good;
    for (int i = 0; i < 24; i++) {
      if (board[i] != 0) continue;
      empty.push_back(i);
      if (closesMill(i, me)) win.push_back(i);
      if (closesMill(i, opp)) block.push_back(i);
      if (i % 2 == 1 && i >= 8 && i < 16) good.push_back(i);
    }
    if (!win.empty()) return Action{Action::Place, pick(win), -1};
    if (!block.empty()) return Action{Action::Place, pick(block), -1};
    const bool coin = std::uniform_int_distribution<int>(0, 1)(rng);
    return Action{Action::Place, pick(!good.empty() && coin ? good : empty), -1};
  }
  std::uniform_real_distribution<double> noise(0, 1);
  double best = -1e9;
  std::optional<Action> choice;
  for (int f = 0; f < 24; f++) {
    if (board[f] != me) continue;
    for (int t : targets(f)) {
      Mill g = *this;
      g.board[f] = 0;
      double score = 0;
      if (g.closesMill(t, me)) score += 10;
      if (closesMill(t, opp)) score += 4;
      g.board[t] = me;
      for (int i = 0; i < 24; i++) {
        if (g.board[i] != 0 || !g.closesMill(i, opp)) continue;
        for (int n : neighbours()[i]) {
          if (g.board[n] == opp) {
            score -= 3;
            break;
          }
        }
      }
      score += noise(rng);
      if (score > best) {
        best = score;
        choice = Action{Action::Move, f, t};
      }
    }
  }
  return choice;
}

// -------------------------------------------------------------------- Kniffel

const char* kniffelLabel(int c) {
  static const char* labels[] = {"Einser", "Zweier", "Dreier", "Vierer", "Fünfer",
                                 "Sechser", "Dreierpasch", "Viererpasch",
                                 "Full House", "Kleine Straße", "Große Straße",
                                 "Kniffel", "Chance"};
  return labels[c];
}

int kniffelScore(int cat, const std::array<int, 5>& dice) {
  int counts[7] = {};
  int sum = 0;
  for (int d : dice) {
    counts[d]++;
    sum += d;
  }
  auto hasRun = [&](int len) {
    int run = 0;
    for (int v = 1; v <= 6; v++) {
      run = counts[v] > 0 ? run + 1 : 0;
      if (run >= len) return true;
    }
    return false;
  };
  auto any = [&](int n) {
    for (int v = 1; v <= 6; v++) {
      if (counts[v] >= n) return true;
    }
    return false;
  };
  auto exact = [&](int n) {
    for (int v = 1; v <= 6; v++) {
      if (counts[v] == n) return true;
    }
    return false;
  };
  if (cat <= Sixes) return counts[cat + 1] * (cat + 1);
  switch (cat) {
    case ThreeKind: return any(3) ? sum : 0;
    case FourKind: return any(4) ? sum : 0;
    case FullHouse: return exact(3) && exact(2) ? 25 : 0;
    case SmallStraight: return hasRun(4) ? 30 : 0;
    case LargeStraight: return hasRun(5) ? 40 : 0;
    case Kniffel5: return exact(5) ? 50 : 0;
    default: return sum;  // Chance
  }
}

bool KniffelSheet::complete() const {
  for (int e : entries) {
    if (e < 0) return false;
  }
  return true;
}

int KniffelSheet::upperSum() const {
  int s = 0;
  for (int c = Ones; c <= Sixes; c++) s += std::max(0, entries[c]);
  return s;
}

int KniffelSheet::lowerSum() const {
  int s = 0;
  for (int c = ThreeKind; c < CatCount; c++) s += std::max(0, entries[c]);
  return s;
}

KniffelGame::KniffelGame(int p, uint32_t seed) : players(p), sheets(p), rng_(seed) {}

bool KniffelGame::isOver() const {
  for (auto& s : sheets) {
    if (!s.complete()) return false;
  }
  return true;
}

void KniffelGame::roll() {
  if (!canRoll()) return;
  std::uniform_int_distribution<int> die(1, 6);
  const bool first = !hasRolled();
  if (first) held = {};
  for (int i = 0; i < 5; i++) {
    if (!held[i]) dice[i] = die(rng_);
  }
  rollsLeft--;
}

void KniffelGame::toggleHold(int i) {
  if (!hasRolled() || rollsLeft == 0) return;
  held[i] = !held[i];
}

bool KniffelGame::score(int c) {
  if (!canScore(c)) return false;
  sheets[current].entries[c] = kniffelScore(c, dice);
  current = (current + 1) % players;
  rollsLeft = 3;
  held = {};
  return true;
}

std::vector<int> KniffelGame::winners() const {
  int best = -1;
  for (auto& s : sheets) best = std::max(best, s.total());
  std::vector<int> out;
  for (int i = 0; i < players; i++) {
    if (sheets[i].total() == best) out.push_back(i);
  }
  return out;
}

namespace {
const double KniffelPar[CatCount] = {2, 5, 8, 11, 14, 17, 15, 6, 9, 14, 10, 7, 22};

double kniffelValue(int c, const std::array<int, 5>& dice, const KniffelSheet& sheet) {
  const double raw = kniffelScore(c, dice);
  double v = raw - KniffelPar[c];
  if (c <= Sixes) {
    const int face = c + 1;
    if (raw >= face * 3) v += 4;
    if (sheet.bonus() == 0 && sheet.upperSum() + raw >= 63) v += 20;
  }
  return v;
}

std::pair<int, double> bestCategory(const std::array<int, 5>& dice,
                                    const KniffelSheet& sheet) {
  int best = -1;
  double bestV = -1e18;
  for (int c = 0; c < CatCount; c++) {
    if (sheet.filled(c)) continue;
    const double v = kniffelValue(c, dice, sheet);
    if (v > bestV) {
      bestV = v;
      best = c;
    }
  }
  return {best, bestV};
}
}  // namespace

std::array<bool, 5> KniffelGame::aiHolds(std::mt19937& rng) const {
  std::uniform_int_distribution<int> die(1, 6);
  const KniffelSheet& sheet = sheets[current];
  int bestMask = 0;
  double bestScore = -1e18;
  for (int mask = 0; mask < 32; mask++) {
    const int n = mask == 31 ? 1 : 60;
    double total = 0;
    for (int s = 0; s < n; s++) {
      auto d = dice;
      for (int r = 0; r < (rollsLeft > 1 ? 2 : 1); r++) {
        for (int i = 0; i < 5; i++) {
          if (!((mask >> i) & 1)) d[i] = die(rng);
        }
      }
      total += bestCategory(d, sheet).second;
    }
    if (total / n > bestScore) {
      bestScore = total / n;
      bestMask = mask;
    }
  }
  std::array<bool, 5> h{};
  for (int i = 0; i < 5; i++) h[i] = (bestMask >> i) & 1;
  return h;
}

int KniffelGame::aiCategory() const { return bestCategory(dice, sheets[current]).first; }

// --------------------------------------------------------------------- Schach

namespace {
bool white(char p) { return p >= 'A' && p <= 'Z'; }
int fileOf(int sq) { return sq % 8; }
int rankOf(int sq) { return sq / 8; }
}  // namespace

ChessPos::ChessPos() {
  const char* back = "RNBQKBNR";
  for (int f = 0; f < 8; f++) {
    board[f] = back[f];
    board[8 + f] = 'P';
    board[48 + f] = 'p';
    board[56 + f] = char(std::tolower(back[f]));
  }
}

int ChessPos::kingSquare(bool w) const {
  for (int i = 0; i < 64; i++) {
    if (board[i] == (w ? 'K' : 'k')) return i;
  }
  return -1;
}

bool ChessPos::attacked(int sq, bool byWhite) const {
  const int f = fileOf(sq), r = rankOf(sq);
  auto at = [&](int ff, int rr) -> char {
    if (ff < 0 || ff > 7 || rr < 0 || rr > 7) return 0;
    return board[rr * 8 + ff];
  };
  auto mine = [&](char p, char upper) {
    return p != 0 && std::toupper(p) == upper && white(p) == byWhite;
  };
  // Pawns
  const int pr = byWhite ? r - 1 : r + 1;
  if (mine(at(f - 1, pr), 'P') || mine(at(f + 1, pr), 'P')) return true;
  // Knights
  static const int kn[8][2] = {{1, 2}, {2, 1}, {2, -1}, {1, -2},
                               {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
  for (auto& d : kn) {
    if (mine(at(f + d[0], r + d[1]), 'N')) return true;
  }
  // King
  for (int df = -1; df <= 1; df++) {
    for (int dr = -1; dr <= 1; dr++) {
      if ((df || dr) && mine(at(f + df, r + dr), 'K')) return true;
    }
  }
  // Sliders
  static const int diag[4][2] = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}};
  static const int orth[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
  for (auto& d : diag) {
    int ff = f + d[0], rr = r + d[1];
    while (ff >= 0 && ff < 8 && rr >= 0 && rr < 8) {
      const char p = board[rr * 8 + ff];
      if (p) {
        if (mine(p, 'B') || mine(p, 'Q')) return true;
        break;
      }
      ff += d[0];
      rr += d[1];
    }
  }
  for (auto& d : orth) {
    int ff = f + d[0], rr = r + d[1];
    while (ff >= 0 && ff < 8 && rr >= 0 && rr < 8) {
      const char p = board[rr * 8 + ff];
      if (p) {
        if (mine(p, 'R') || mine(p, 'Q')) return true;
        break;
      }
      ff += d[0];
      rr += d[1];
    }
  }
  return false;
}

bool ChessPos::inCheck() const {
  const int k = kingSquare(whiteToMove);
  return k >= 0 && attacked(k, !whiteToMove);
}

void ChessPos::pseudoMoves(std::vector<ChessMove>& out) const {
  const bool w = whiteToMove;
  auto own = [&](int sq) { return board[sq] && white(board[sq]) == w; };
  auto enemy = [&](int sq) { return board[sq] && white(board[sq]) != w; };
  auto add = [&](int from, int to) {
    const bool pawn = std::toupper(board[from]) == 'P';
    if (pawn && (rankOf(to) == 7 || rankOf(to) == 0)) {
      for (char p : {'q', 'r', 'b', 'n'}) out.push_back({from, to, p});
    } else {
      out.push_back({from, to, 0});
    }
  };
  for (int sq = 0; sq < 64; sq++) {
    const char p = board[sq];
    if (!p || white(p) != w) continue;
    const int f = fileOf(sq), r = rankOf(sq);
    switch (std::toupper(p)) {
      case 'P': {
        const int dir = w ? 1 : -1, start = w ? 1 : 6;
        const int one = sq + dir * 8;
        if (one >= 0 && one < 64 && !board[one]) {
          add(sq, one);
          const int two = sq + dir * 16;
          if (r == start && !board[two]) add(sq, two);
        }
        for (int df : {-1, 1}) {
          const int ff = f + df, rr = r + dir;
          if (ff < 0 || ff > 7 || rr < 0 || rr > 7) continue;
          const int to = rr * 8 + ff;
          if (enemy(to) || to == epSquare) add(sq, to);
        }
        break;
      }
      case 'N': {
        static const int kn[8][2] = {{1, 2}, {2, 1}, {2, -1}, {1, -2},
                                     {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
        for (auto& d : kn) {
          const int ff = f + d[0], rr = r + d[1];
          if (ff < 0 || ff > 7 || rr < 0 || rr > 7) continue;
          if (!own(rr * 8 + ff)) add(sq, rr * 8 + ff);
        }
        break;
      }
      case 'K': {
        for (int df = -1; df <= 1; df++) {
          for (int dr = -1; dr <= 1; dr++) {
            const int ff = f + df, rr = r + dr;
            if ((!df && !dr) || ff < 0 || ff > 7 || rr < 0 || rr > 7) continue;
            if (!own(rr * 8 + ff)) add(sq, rr * 8 + ff);
          }
        }
        // Castling: path empty, king not in, through or into check.
        const int home = w ? 4 : 60;
        if (sq == home && !attacked(home, !w)) {
          const bool k = w ? castleWK : castleBK, q = w ? castleWQ : castleBQ;
          const char rook = w ? 'R' : 'r';
          if (k && board[home + 3] == rook && !board[home + 1] && !board[home + 2] &&
              !attacked(home + 1, !w) && !attacked(home + 2, !w)) {
            add(sq, home + 2);
          }
          if (q && board[home - 4] == rook && !board[home - 1] && !board[home - 2] &&
              !board[home - 3] && !attacked(home - 1, !w) && !attacked(home - 2, !w)) {
            add(sq, home - 2);
          }
        }
        break;
      }
      default: {
        static const int dirs[8][2] = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1},
                                       {1, 0}, {-1, 0}, {0, 1}, {0, -1}};
        const char t = char(std::toupper(p));
        const int first = t == 'R' ? 4 : 0, last = t == 'B' ? 4 : 8;
        for (int i = first; i < last; i++) {
          int ff = f + dirs[i][0], rr = r + dirs[i][1];
          while (ff >= 0 && ff < 8 && rr >= 0 && rr < 8) {
            const int to = rr * 8 + ff;
            if (own(to)) break;
            add(sq, to);
            if (board[to]) break;
            ff += dirs[i][0];
            rr += dirs[i][1];
          }
        }
      }
    }
  }
}

void ChessPos::apply(const ChessMove& m) {
  const char p = board[m.from];
  const bool w = white(p);
  const char t = char(std::toupper(p));
  const bool capture = board[m.to] != 0;
  // En passant: the captured pawn stands behind the target square.
  if (t == 'P' && m.to == epSquare && !board[m.to]) {
    board[m.to + (w ? -8 : 8)] = 0;
  }
  // Castling moves the rook too.
  if (t == 'K' && std::abs(m.to - m.from) == 2) {
    if (m.to > m.from) {
      board[m.from + 1] = board[m.from + 3];
      board[m.from + 3] = 0;
    } else {
      board[m.from - 1] = board[m.from - 4];
      board[m.from - 4] = 0;
    }
  }
  board[m.to] = p;
  board[m.from] = 0;
  if (t == 'P' && (rankOf(m.to) == 7 || rankOf(m.to) == 0)) {
    const char promo = m.promotion ? m.promotion : 'q';
    board[m.to] = w ? char(std::toupper(promo)) : promo;
  }
  // Castling rights.
  auto touched = [&](int sq) { return m.from == sq || m.to == sq; };
  if (touched(4)) castleWK = castleWQ = false;
  if (touched(60)) castleBK = castleBQ = false;
  if (touched(0)) castleWQ = false;
  if (touched(7)) castleWK = false;
  if (touched(56)) castleBQ = false;
  if (touched(63)) castleBK = false;
  epSquare = (t == 'P' && std::abs(m.to - m.from) == 16) ? (m.from + m.to) / 2 : -1;
  halfmoves = (t == 'P' || capture) ? 0 : halfmoves + 1;
  whiteToMove = !whiteToMove;
}

bool ChessPos::legal(const ChessMove& m) const {
  ChessPos c = *this;
  c.apply(m);
  const int k = c.kingSquare(whiteToMove);
  return k >= 0 && !c.attacked(k, !whiteToMove);
}

std::vector<ChessMove> ChessPos::legalMoves() const {
  std::vector<ChessMove> pseudo, out;
  pseudoMoves(pseudo);
  for (auto& m : pseudo) {
    if (legal(m)) out.push_back(m);
  }
  return out;
}

bool ChessPos::hasLegalMove() const {
  std::vector<ChessMove> pseudo;
  pseudoMoves(pseudo);
  for (auto& m : pseudo) {
    if (legal(m)) return true;
  }
  return false;
}

bool ChessPos::isPromotion(int from, int to) const {
  return std::toupper(board[from]) == 'P' && (rankOf(to) == 7 || rankOf(to) == 0);
}

bool ChessPos::insufficientMaterial() const {
  int minors = 0;
  for (char p : board) {
    if (!p) continue;
    const char t = char(std::toupper(p));
    if (t == 'K') continue;
    if (t == 'N' || t == 'B') {
      minors++;
    } else {
      return false;
    }
  }
  return minors <= 1;
}

double ChessPos::material(bool forWhite) const {
  double score = 0;
  for (int sq = 0; sq < 64; sq++) {
    const char p = board[sq];
    if (!p) continue;
    double v = 0;
    switch (std::toupper(p)) {
      case 'P': v = 1; break;
      case 'N': v = 3; break;
      case 'B': v = 3.2; break;
      case 'R': v = 5; break;
      case 'Q': v = 9; break;
      default: v = 0;
    }
    const int f = fileOf(sq), r = rankOf(sq);
    if (f >= 2 && f <= 5 && r >= 2 && r <= 5) v += 0.1;
    score += white(p) == forWhite ? v : -v;
  }
  return score;
}

double ChessPos::position(bool forWhite) const {
  double score = 0;
  for (int sq = 0; sq < 64; sq++) {
    const char p = board[sq];
    if (!p) continue;
    const bool w = white(p);
    const int f = fileOf(sq), r = rankOf(sq);
    const int own = w ? r : 7 - r;  // rank from the owner's side
    const double centre = 3.5 - std::max(std::abs(f - 3.5), std::abs(r - 3.5));
    double v = 0;
    switch (std::toupper(p)) {
      case 'P': v = 1 + own * 0.05 + (f >= 3 && f <= 4 ? 0.1 : 0); break;
      case 'N': v = 3 + centre * 0.08 + (own == 0 ? -0.25 : 0); break;
      case 'B': v = 3.2 + centre * 0.08 + (own == 0 ? -0.25 : 0); break;
      case 'R': v = 5 + centre * 0.02; break;
      case 'Q': v = 9 + centre * 0.03; break;
      default: v = (own == 0 ? 0.2 : -0.1 * own) + (f <= 2 || f >= 6 ? 0.2 : 0);  // king
    }
    score += w == forWhite ? v : -v;
  }
  if (inCheck()) score += whiteToMove == forWhite ? -0.3 : 0.3;
  return score;
}

std::string ChessPos::key() const {
  std::string k(board.begin(), board.end());
  for (char& c : k) {
    if (!c) c = '.';
  }
  k += whiteToMove ? 'w' : 'b';
  k += castleWK ? 'K' : '-';
  k += castleWQ ? 'Q' : '-';
  k += castleBK ? 'k' : '-';
  k += castleBQ ? 'q' : '-';
  k += std::to_string(epSquare);
  return k;
}

Chess::Chess() { seen_[key()] = 1; }

std::vector<ChessMove> Chess::movesFrom(int square) const {
  std::vector<ChessMove> out;
  for (auto& m : legalMoves()) {
    if (m.from == square) out.push_back(m);
  }
  return out;
}

bool Chess::play(ChessMove m) {
  if (isOver()) return false;
  if (isPromotion(m.from, m.to) && !m.promotion) m.promotion = 'q';
  if (!isPromotion(m.from, m.to)) m.promotion = 0;
  for (auto& l : legalMoves()) {
    if (l.from == m.from && l.to == m.to && l.promotion == m.promotion) {
      apply(l);
      lastFrom = l.from;
      lastTo = l.to;
      seen_[key()]++;
      return true;
    }
  }
  return false;
}

bool Chess::draw() const {
  if (stalemate() || halfmoves >= 100 || insufficientMaterial()) return true;
  auto it = seen_.find(key());
  return it != seen_.end() && it->second >= 3;
}

ChessMove Chess::aiMove(std::mt19937& rng) const {
  const auto moves = legalMoves();
  const bool me = whiteToMove;
  std::uniform_real_distribution<double> noise(0, 0.3);
  double best = -1e18;
  ChessMove choice = moves.front();
  for (auto& m : moves) {
    ChessPos c = *this;
    c.apply(m);
    double score;
    const bool hasMove = c.hasLegalMove();
    if (!hasMove && c.inCheck()) {
      score = 1e6;
    } else if (!hasMove || c.insufficientMaterial()) {
      score = 0;
    } else {
      // Assume the opponent answers with its best reply.
      double worst = 1e18;
      for (auto& reply : c.legalMoves()) {
        ChessPos c2 = c;
        c2.apply(reply);
        double s;
        if (c2.inCheck() && !c2.hasLegalMove()) {
          s = -1e6;
        } else {
          s = c2.material(me);
        }
        worst = std::min(worst, s);
      }
      score = worst;
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
double chessSearch(const ChessPos& p, int depth, double alpha, double beta, bool me) {
  auto moves = p.legalMoves();
  if (moves.empty()) return p.inCheck() ? (p.whiteToMove == me ? -1e6 - depth : 1e6 + depth) : 0;
  if (depth == 0 || p.insufficientMaterial()) return p.position(me);
  // Captures first: better pruning.
  std::stable_sort(moves.begin(), moves.end(), [&](const ChessMove& a, const ChessMove& b) {
    return (p.board[a.to] != 0) > (p.board[b.to] != 0);
  });
  const bool maximizing = p.whiteToMove == me;
  double v = maximizing ? -1e18 : 1e18;
  for (auto& m : moves) {
    ChessPos c = p;
    c.apply(m);
    const double s = chessSearch(c, depth - 1, alpha, beta, me);
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

ChessMove Chess::strongMove(std::mt19937& rng) const {
  const auto moves = legalMoves();
  const bool me = whiteToMove;
  std::uniform_real_distribution<double> noise(0, 0.02);
  double best = -1e18;
  ChessMove choice = moves.front();
  for (auto& m : moves) {
    ChessPos c = *this;
    c.apply(m);
    const double s = chessSearch(c, 2, -1e18, 1e18, me) + noise(rng);
    if (s > best) {
      best = s;
      choice = m;
    }
  }
  return choice;
}

// ------------------------------------------------------- Schiffe versenken

const Ship* Fleet::shipAt(int x, int y) const {
  for (auto& s : ships) {
    if (std::find(s.cells.begin(), s.cells.end(), Cell{x, y}) != s.cells.end()) {
      return &s;
    }
  }
  return nullptr;
}

bool Fleet::canPlace(const std::vector<Cell>& cells) const {
  for (auto [x, y] : cells) {
    if (x < 0 || y < 0 || x >= SeaSize || y >= SeaSize) return false;
    // Ships may not touch, not even diagonally.
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (shipAt(x + dx, y + dy)) return false;
      }
    }
  }
  return true;
}

bool Fleet::place(int x, int y, int len, bool horizontal) {
  std::vector<Cell> cells;
  for (int i = 0; i < len; i++) cells.push_back(horizontal ? Cell{x + i, y} : Cell{x, y + i});
  if (!canPlace(cells)) return false;
  ships.push_back({cells, {}});
  return true;
}

Fleet Fleet::random(std::mt19937& rng) {
  std::uniform_int_distribution<int> coord(0, SeaSize - 1), coin(0, 1);
  while (true) {
    Fleet f;
    bool ok = true;
    for (int len : FleetSizes) {
      bool placed = false;
      for (int a = 0; a < 200 && !placed; a++) {
        placed = f.place(coord(rng), coord(rng), len, coin(rng));
      }
      if (!placed) {
        ok = false;
        break;
      }
    }
    if (ok) return f;
  }
}

bool Fleet::allSunk() const {
  if (ships.empty()) return false;
  for (auto& s : ships) {
    if (!s.sunk()) return false;
  }
  return true;
}

bool Fleet::shotAt(int x, int y) const {
  return std::find(shots.begin(), shots.end(), Cell{x, y}) != shots.end();
}

Shot Fleet::receive(int x, int y, std::vector<Cell>* sunkCells) {
  shots.push_back({x, y});
  for (auto& s : ships) {
    if (std::find(s.cells.begin(), s.cells.end(), Cell{x, y}) == s.cells.end()) continue;
    if (std::find(s.hits.begin(), s.hits.end(), Cell{x, y}) == s.hits.end()) {
      s.hits.push_back({x, y});
    }
    if (s.sunk()) {
      if (sunkCells) *sunkCells = s.cells;
      return Shot::Sunk;
    }
    return Shot::Hit;
  }
  return Shot::Miss;
}

void Chart::apply(int x, int y, Shot s, const std::vector<Cell>& sunk) {
  switch (s) {
    case Shot::Miss: cells[y][x] = Mark::Miss; break;
    case Shot::Hit: cells[y][x] = Mark::Hit; break;
    case Shot::Sunk:
      for (auto [sx, sy] : sunk) cells[sy][sx] = Mark::Sunk;
      // Water around a sunk ship.
      for (auto [sx, sy] : sunk) {
        for (int dx = -1; dx <= 1; dx++) {
          for (int dy = -1; dy <= 1; dy++) {
            const int nx = sx + dx, ny = sy + dy;
            if (nx >= 0 && ny >= 0 && nx < SeaSize && ny < SeaSize &&
                cells[ny][nx] == Mark::Unknown) {
              cells[ny][nx] = Mark::Miss;
            }
          }
        }
      }
      break;
  }
}

Cell battleshipAiShot(const Chart& k, std::mt19937& rng) {
  auto pick = [&](const std::vector<Cell>& v) {
    return v[std::uniform_int_distribution<size_t>(0, v.size() - 1)(rng)];
  };
  std::vector<Cell> hits;
  for (int y = 0; y < SeaSize; y++) {
    for (int x = 0; x < SeaSize; x++) {
      if (k.cells[y][x] == Mark::Hit) hits.push_back({x, y});
    }
  }
  if (!hits.empty()) {
    bool horizontal = hits.size() > 1, vertical = hits.size() > 1;
    for (auto& h : hits) {
      horizontal &= h.second == hits.front().second;
      vertical &= h.first == hits.front().first;
    }
    std::vector<Cell> candidates;
    for (auto [x, y] : hits) {
      std::vector<Cell> dirs;
      if (horizontal) {
        dirs = {{1, 0}, {-1, 0}};
      } else if (vertical) {
        dirs = {{0, 1}, {0, -1}};
      } else {
        dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
      }
      for (auto [dx, dy] : dirs) {
        const int nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < SeaSize && ny < SeaSize && k.canShoot(nx, ny)) {
          candidates.push_back({nx, ny});
        }
      }
    }
    if (!candidates.empty()) return pick(candidates);
  }
  // Hunt on a checkerboard: every ship covers at least one such cell.
  std::vector<Cell> open, parity;
  for (int y = 0; y < SeaSize; y++) {
    for (int x = 0; x < SeaSize; x++) {
      if (!k.canShoot(x, y)) continue;
      open.push_back({x, y});
      if ((x + y) % 2 == 0) parity.push_back({x, y});
    }
  }
  return pick(parity.empty() ? open : parity);
}

// -------------------------------------------------------------------- Solitär

Klondike::Klondike(int dc, uint32_t seed) : drawCount(dc) {
  std::vector<Card> deck;
  for (int s = 0; s < 4; s++) {
    for (int r = 1; r <= 13; r++) deck.push_back({s, r, false});
  }
  std::mt19937 rng(seed);
  std::shuffle(deck.begin(), deck.end(), rng);
  for (int i = 0; i < 7; i++) {
    for (int j = i; j < 7; j++) {
      tableau[j].push_back(deck.back());
      deck.pop_back();
    }
    tableau[i].back().faceUp = true;
  }
  stock = deck;
}

bool Klondike::won() const {
  for (auto& f : foundations) {
    if (f.size() != 13) return false;
  }
  return true;
}

std::vector<Card>& Klondike::pile(PileRef p) {
  switch (p.kind) {
    case PileKind::Stock: return stock;
    case PileKind::Waste: return waste;
    case PileKind::Foundation: return foundations[p.index];
    default: return tableau[p.index];
  }
}

const std::vector<Card>& Klondike::pile(PileRef p) const {
  return const_cast<Klondike*>(this)->pile(p);
}

bool Klondike::onTableau(const Card& c, int t) const {
  const auto& p = tableau[t];
  if (p.empty()) return c.rank == 13;
  const Card& top = p.back();
  return top.faceUp && top.red() != c.red() && top.rank == c.rank + 1;
}

bool Klondike::onFoundation(const Card& c, int f) const {
  const auto& p = foundations[f];
  if (p.empty()) return c.rank == 1;
  return p.back().suit == c.suit && p.back().rank == c.rank - 1;
}

bool Klondike::movable(PileRef from, int index) const {
  const auto& cards = pile(from);
  if (index < 0 || index >= (int)cards.size()) return false;
  switch (from.kind) {
    case PileKind::Stock: return false;
    case PileKind::Waste:
    case PileKind::Foundation: return index == (int)cards.size() - 1;
    default: return cards[index].faceUp;
  }
}

bool Klondike::canMove(PileRef from, int index, PileRef to) const {
  if (from == to || !movable(from, index)) return false;
  const auto& src = pile(from);
  const int count = int(src.size()) - index;
  switch (to.kind) {
    case PileKind::Foundation: return count == 1 && onFoundation(src[index], to.index);
    case PileKind::Tableau: return onTableau(src[index], to.index);
    default: return false;
  }
}

void Klondike::save() {
  history_.push_back({stock, waste, foundations, tableau, moves, score});
  if (history_.size() > 200) history_.erase(history_.begin());
}

bool Klondike::undo() {
  if (history_.empty()) return false;
  auto& s = history_.back();
  stock = s.stock;
  waste = s.waste;
  foundations = s.foundations;
  tableau = s.tableau;
  moves = s.moves;
  score = s.score;
  history_.pop_back();
  return true;
}

bool Klondike::move(PileRef from, int index, PileRef to) {
  if (!canMove(from, index, to)) return false;
  save();
  auto& src = pile(from);
  auto& dst = pile(to);
  dst.insert(dst.end(), src.begin() + index, src.end());
  src.erase(src.begin() + index, src.end());
  if (to.kind == PileKind::Foundation) {
    addScore(10);
  } else if (from.kind == PileKind::Waste) {
    addScore(5);
  } else if (from.kind == PileKind::Foundation) {
    addScore(-15);
  }
  if (from.kind == PileKind::Tableau && !src.empty() && !src.back().faceUp) {
    src.back().faceUp = true;
    addScore(5);
  }
  moves++;
  return true;
}

bool Klondike::draw() {
  if (stock.empty() && waste.empty()) return false;
  save();
  if (stock.empty()) {
    for (auto it = waste.rbegin(); it != waste.rend(); ++it) {
      Card c = *it;
      c.faceUp = false;
      stock.push_back(c);
    }
    waste.clear();
    addScore(drawCount == 1 ? -100 : -20);
  } else {
    for (int i = 0; i < drawCount && !stock.empty(); i++) {
      Card c = stock.back();
      stock.pop_back();
      c.faceUp = true;
      waste.push_back(c);
    }
  }
  moves++;
  return true;
}

std::optional<PileRef> Klondike::bestTarget(PileRef from, int index) const {
  if (!movable(from, index)) return std::nullopt;
  const int count = int(pile(from).size()) - index;
  if (count == 1 && from.kind != PileKind::Foundation) {
    for (int f = 0; f < 4; f++) {
      PileRef to{PileKind::Foundation, f};
      if (canMove(from, index, to)) return to;
    }
  }
  std::optional<PileRef> empty;
  for (int t = 0; t < 7; t++) {
    PileRef to{PileKind::Tableau, t};
    if (!canMove(from, index, to)) continue;
    if (tableau[t].empty()) {
      // A king that already heads its own column stays.
      if (from.kind == PileKind::Tableau && index == 0) continue;
      if (!empty) empty = to;
      continue;
    }
    return to;
  }
  return empty;
}

bool Klondike::canAutoComplete() const {
  if (won() || !stock.empty() || !waste.empty()) return false;
  for (auto& p : tableau) {
    for (auto& c : p) {
      if (!c.faceUp) return false;
    }
  }
  return true;
}

bool Klondike::autoStep() {
  for (int t = 0; t < 7; t++) {
    if (tableau[t].empty()) continue;
    for (int f = 0; f < 4; f++) {
      if (move({PileKind::Tableau, t}, int(tableau[t].size()) - 1, {PileKind::Foundation, f})) {
        return true;
      }
    }
  }
  return false;
}
