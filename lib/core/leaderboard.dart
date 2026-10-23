import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../games/mahjong/mahjong_logic.dart';
import '../games/snake/snake_logic.dart';
import '../games/solitaire/klondike_logic.dart';
import '../games/yahtzee/kniffel_proof.dart';
import 'account.dart';
import 'legacy_scores.dart';
import 'moderation.dart';
import 'names.dart';
import 'nostr/event.dart';
import 'nostr/relay_pool.dart';
import 'secrets.dart';

/// One ranking, e.g. "Snake – points" or "Darts 501 – darts needed".
class ScoreBoard {
  const ScoreBoard(
    this.id,
    this.game,
    this.title,
    this.unit, {
    this.lowerIsBetter = false,
    this.min = 0,
    this.max = 1 << 30,
    this.legacyKey,
    this.time = false,
    this.secret = false,
    this.proven = false,
  });

  /// Only results with a replayable record of the game count (see
  /// [Leaderboard.verify]); a number typed in somewhere is ignored.
  final bool proven;

  /// Rankings for the Konami extras: only shown after the code was found.
  final bool secret;

  final String id;

  /// Game id from the registry (for grouping and icons).
  final String game;
  final String title;
  final String unit;
  final bool lowerIsBetter;

  /// Values outside this range are ignored (scores can't be verified, so
  /// at least obvious nonsense is filtered out).
  final int min, max;

  /// Old SharedPreferences key holding a best value from before the
  /// leaderboard existed.
  final String? legacyKey;

  /// Value is a duration in seconds.
  final bool time;

  bool better(int a, int b) => lowerIsBetter ? a < b : a > b;
  bool plausible(int v) => v >= min && v <= max;

  String format(int v) {
    if (time) return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
    return '$v $unit';
  }
}

const boards = [
  ScoreBoard(
    'snake',
    'snake',
    'Snake',
    'Punkte',
    max: 5000,
    legacyKey: 'snake.best',
    proven: true,
  ),
  ScoreBoard(
    'klondike',
    'klondike',
    'Solitär',
    'Punkte',
    max: 40000,
    legacyKey: 'klondike.best',
    proven: true,
  ),
  ScoreBoard(
    'kniffel',
    'yahtzee',
    'Würfelkönig allein',
    'Punkte',
    // 375 plus 12 Kniffel bonuses of 100 (13 Kniffel with the joker rule).
    max: 1575,
    proven: true,
  ),
  ScoreBoard(
    'mahjong.tower',
    'mahjong',
    'Mahjong Pyramide',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
    proven: true,
  ),
  ScoreBoard(
    'mahjong.pyramid',
    'mahjong',
    'Mahjong Breit',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
    proven: true,
  ),
  ScoreBoard(
    'mahjong.turm',
    'mahjong',
    'Mahjong Turm',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
    proven: true,
  ),
  ScoreBoard(
    'arrows.easy',
    'arrows',
    'Pfeile Leicht',
    'Level',
    min: 1,
    max: 100000,
  ),
  ScoreBoard(
    'arrows.medium',
    'arrows',
    'Pfeile Mittel',
    'Level',
    min: 1,
    max: 100000,
  ),
  ScoreBoard(
    'arrows.hard',
    'arrows',
    'Pfeile Schwer',
    'Level',
    min: 1,
    max: 100000,
  ),
  ScoreBoard(
    'arrows.extreme',
    'arrows',
    'Pfeile Extrem',
    'Level',
    min: 1,
    max: 100000,
  ),
  ScoreBoard(
    'arrows.insane',
    'arrows',
    'Pfeile Wahnsinn',
    'Level',
    min: 1,
    max: 100000,
  ),
  ScoreBoard(
    'labyrinth',
    'labyrinth',
    'Kugellabyrinth',
    'Level',
    min: 1,
    max: 200,
  ),
  ScoreBoard(
    'darts.x501',
    'darts',
    'Darts 501',
    'Darts',
    lowerIsBetter: true,
    min: 9,
    max: 2000,
    legacyKey: 'darts.best.x501',
  ),
  ScoreBoard(
    'darts.x301',
    'darts',
    'Darts 301',
    'Darts',
    lowerIsBetter: true,
    min: 6,
    max: 2000,
    legacyKey: 'darts.best.x301',
  ),
  ScoreBoard(
    'darts.aroundTheClock',
    'darts',
    'Darts Rund um die Uhr',
    'Darts',
    lowerIsBetter: true,
    min: 7,
    max: 2000,
    legacyKey: 'darts.best.aroundTheClock',
  ),
  ScoreBoard(
    'billiard.eightLast',
    'billiard',
    'Billard 8 zum Schluss',
    'Punkte',
    lowerIsBetter: true,
    min: 1,
    max: 1000,
    legacyKey: 'billiard.best.eightLast',
  ),
  ScoreBoard(
    'billiard.rotation',
    'billiard',
    'Billard Reihenfolge',
    'Punkte',
    lowerIsBetter: true,
    min: 1,
    max: 1000,
    legacyKey: 'billiard.best.rotation',
  ),
  // The harder Konami extras get their own rankings.
  ScoreBoard(
    'labyrinth.nightmare',
    'labyrinth',
    'Labyrinth Albtraum 🎮',
    'Level',
    min: 1,
    max: 200,
    secret: true,
  ),
  ScoreBoard(
    'labyrinth.rubber',
    'labyrinth',
    'Labyrinth Gummiball 🎮',
    'Level',
    min: 1,
    max: 200,
    secret: true,
  ),
  ScoreBoard(
    'chess.grandmaster',
    'chess',
    'Schach vs. Großmeister 🎮',
    'Siege',
    min: 1,
    max: 100000,
    secret: true,
  ),
  ScoreBoard(
    'checkers.grandmaster',
    'checkers',
    'Dame vs. Großmeister 🎮',
    'Siege',
    min: 1,
    max: 100000,
    secret: true,
  ),
  ScoreBoard(
    'kniffel.lucky',
    'yahtzee',
    'Würfelkönig vs. Glückspilz 🎮',
    'Siege',
    min: 1,
    max: 100000,
    secret: true,
  ),
];

/// Boards the player may see (secret ones only after the Konami code).
List<ScoreBoard> visibleBoards() => [
  for (final b in boards)
    if (!b.secret || Secrets.I.unlocked) b,
];

ScoreBoard boardById(String id) => boards.firstWhere((b) => b.id == id);

ScoreBoard? boardOrNull(String id) =>
    boards.where((b) => b.id == id).firstOrNull;

/// A result in the personal list.
class ScoreEntry {
  ScoreEntry(this.value, this.at, {this.proof});
  final int value;
  final DateTime at;

  /// Record of the game for boards that check results (see
  /// [ScoreBoard.proven]).
  final Map<String, dynamic>? proof;

  Map<String, dynamic> toJson() => {
    'v': value,
    't': at.millisecondsSinceEpoch,
    'p': ?proof,
  };
  factory ScoreEntry.fromJson(Map<String, dynamic> j) => ScoreEntry(
    j['v'] as int,
    DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
    proof: j['p'] as Map<String, dynamic>?,
  );
}

/// A player's published best values.
class RemoteScores {
  RemoteScores(
    this.pubkey,
    this.name,
    this.scores,
    this.createdAt, {
    this.badge = false,
    this.proofs = const {},
    this.unchecked = const {},
  });

  /// Results on checked boards that can't be shown (no recorded game, not
  /// approved): for the admins to approve (board id → value).
  final Map<String, int> unchecked;

  /// Records of the games behind checked results (board id → record).
  final Map<String, Map<String, dynamic>> proofs;
  final String pubkey;
  final String name;

  /// Found the Konami code (🎮).
  final bool badge;
  final Map<String, int> scores;
  final int createdAt;
}

/// Personal results (on the device) plus a shared ranking without a server:
/// each player publishes their best values as a replaceable Nostr event
/// (NIP-78, kind 30078), others read them from the relays.
///
/// Scores can't be verified – anybody could publish fake values – so the
/// friends list is the more meaningful ranking.
class Leaderboard {
  Leaderboard(this.client, this.account);

  static const kind = 30078;
  static const _d = 'mobilegames-scores';
  static const _t = 'mobilegames-scores';
  static const keep = 10;

  final NostrClient client;
  final Account account;

  /// Called after a new personal best (set by [Services]).
  static Leaderboard? instance;

  /// Whose games are recorded for checked boards (see [ScoreBoard.proven]).
  static String get proofOwner => instance?.account.keys.publicKey ?? 'offline';

  // ---------------------------------------------------------------- local

  static String _key(String id) => 'lb.$id';

  static Future<List<ScoreEntry>> history(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return _history(prefs, boardById(id));
  }

  static List<ScoreEntry> _history(SharedPreferences prefs, ScoreBoard b) {
    final raw = prefs.getString(_key(b.id));
    if (raw != null) {
      try {
        return [
          for (final e in jsonDecode(raw) as List)
            ScoreEntry.fromJson(e as Map<String, dynamic>),
        ];
      } catch (_) {}
    }
    final legacy = b.legacyKey == null ? null : prefs.getInt(b.legacyKey!);
    if (legacy != null && b.plausible(legacy)) {
      return [ScoreEntry(legacy, DateTime.fromMillisecondsSinceEpoch(0))];
    }
    return [];
  }

  static Future<int?> best(String id) async {
    final h = await history(id);
    return h.isEmpty ? null : h.first.value;
  }

  /// All personal bests (board id → value).
  static Future<Map<String, int>> bests() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final b in boards)
        if (_history(prefs, b) case final h when h.isNotEmpty)
          b.id: h.first.value,
    };
  }

  /// Counts one more win for a "wins" board and records the total.
  static Future<bool> recordWin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final wins = (prefs.getInt('wins.$id') ?? 0) + 1;
    await prefs.setInt('wins.$id', wins);
    return submit(id, wins);
  }

  /// Records a finished game. Returns true for a new personal best.
  static Future<bool> submit(
    String id,
    int value, {
    DateTime? at,
    Map<String, dynamic>? proof,
  }) async {
    final b = boardById(id);
    if (!b.plausible(value)) return false;
    final prefs = await SharedPreferences.getInstance();
    final record = await _add(
      prefs,
      b,
      value,
      at ?? DateTime.now(),
      proof: proof,
    );
    if (record) unawaited(instance?.publish());
    return record;
  }

  /// Adds [value] to the history of [b]; true if it is the new best.
  static Future<bool> _add(
    SharedPreferences prefs,
    ScoreBoard b,
    int value,
    DateTime at, {
    Map<String, dynamic>? proof,
  }) async {
    final list = _history(prefs, b);
    final record = list.isEmpty || b.better(value, list.first.value);
    list
      ..add(ScoreEntry(value, at, proof: proof))
      ..sort(
        (x, y) => x.value == y.value
            ? x.at.compareTo(y.at)
            : (b.better(x.value, y.value) ? -1 : 1),
      );
    if (list.length > keep) list.removeRange(keep, list.length);
    await prefs.setString(_key(b.id), jsonEncode(list));
    return record;
  }

  /// Takes over best values this account published before (on another
  /// phone or before a reinstall) where they beat the ones on this device.
  /// Returns how many boards changed.
  static Future<int> adopt(
    Map<String, int> scores,
    DateTime at, {
    Map<String, Map<String, dynamic>> proofs = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var changed = 0;
    for (final MapEntry(key: id, :value) in scores.entries) {
      final b = boards.where((b) => b.id == id).firstOrNull;
      if (b == null || !b.plausible(value)) continue;
      final h = _history(prefs, b);
      if (h.isNotEmpty && !b.better(value, h.first.value)) continue;
      await _add(prefs, b, value, at, proof: proofs[id]);
      // Win counters go on from the number reached.
      if (b.unit == 'Siege' && (prefs.getInt('wins.$id') ?? 0) < value) {
        await prefs.setInt('wins.$id', value);
      }
      changed++;
    }
    return changed;
  }

  // --------------------------------------------------------------- shared

  /// Whether our earlier published values were looked up (see [syncOwn]).
  bool _synced = false;

  /// Fetches the values this account published before and takes them over
  /// (see [adopt]): after moving to a new phone the own results come back,
  /// and the next publish does not replace them with lower ones.
  Future<bool> syncOwn({Duration timeout = const Duration(seconds: 3)}) async {
    final own = await fetch(
      authors: [account.keys.publicKey],
      timeout: timeout,
    );
    if (own.isEmpty) return false;
    final latest = own.reduce((a, b) => a.createdAt >= b.createdAt ? a : b);
    await adopt(
      latest.scores,
      DateTime.fromMillisecondsSinceEpoch(latest.createdAt * 1000),
      proofs: latest.proofs,
    );
    return _synced = true;
  }

  /// Publishes our best values (replaces the previous event).
  Future<void> publish() async {
    // Until our earlier values were seen, merge them in first so they are
    // never replaced with fewer or lower ones.
    if (!_synced) await syncOwn();
    final prefs = await SharedPreferences.getInstance();
    final scores = <String, int>{};
    final proofs = <String, Map<String, dynamic>>{};
    final unchecked = <String, int>{};
    for (final b in boards) {
      final h = _history(prefs, b);
      if (h.isEmpty) continue;
      // A better value that doesn't count (yet): sent along so an admin
      // can approve it, e.g. a record from an older app version.
      if (!counts(b, h.first, account.keys.publicKey)) {
        unchecked[b.id] = h.first.value;
      }
      final best = b.proven
          ? h.where((e) => counts(b, e, account.keys.publicKey)).firstOrNull
          : h.first;
      // Checked boards: only results that come with their game (or old
      // ones kept from before the check, see [legacyScores]).
      if (best == null) continue;
      scores[b.id] = best.value;
      if (best.proof case final p?) proofs[b.id] = p;
    }
    if (scores.isEmpty && unchecked.isEmpty) return;
    await client.publish(
      NostrEvent.create(
        keys: account.keys,
        kind: kind,
        content: jsonEncode({
          'name': account.name,
          's': scores,
          if (proofs.isNotEmpty) 'p': proofs,
          if (unchecked.isNotEmpty) 'u': unchecked,
          if (Secrets.I.unlocked) 'k': true,
        }),
        tags: [
          ['d', _d],
          ['t', _t],
        ],
      ),
    );
    // Our event now holds everything we have.
    _synced = true;
  }

  /// Collects published scores from the relays for [timeout]. With
  /// [authors] only those players are asked for.
  Future<List<RemoteScores>> fetch({
    List<String>? authors,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final latest = <String, RemoteScores>{};
    final sub = client
        .subscribe({
          'kinds': [kind],
          '#t': [_t],
          'authors': ?authors,
          'limit': 500,
        })
        .listen((e) {
          if (!e.tags.any((t) => t.length > 1 && t[0] == 'd' && t[1] == _d)) {
            return;
          }
          if (Moderation.I.isBlocked(e.pubkey)) return;
          final prev = latest[e.pubkey];
          if (prev != null && prev.createdAt >= e.createdAt) return;
          try {
            final j = jsonDecode(e.content) as Map<String, dynamic>;
            final s = <String, int>{};
            final proofs = <String, Map<String, dynamic>>{};
            final unchecked = <String, int>{};
            final sent = j['p'] is Map ? j['p'] as Map : const {};
            for (final MapEntry(:key, :value)
                in (j['s'] as Map<String, dynamic>).entries) {
              final b = boards.where((b) => b.id == key).firstOrNull;
              if (b == null || value is! int || !b.plausible(value)) continue;
              if (b.proven) {
                // Only shown if replaying the game gives exactly this – or
                // if it is no better than the player's value from before.
                final p = sent[key];
                if (p is Map<String, dynamic> &&
                    verify(key, p, e.pubkey) == value) {
                  proofs[key] = p;
                } else if (!_legacyAllows(b, e.pubkey, value)) {
                  unchecked[key] = value;
                  continue;
                }
              }
              s[key] = value;
            }
            // Better values sent for approval: shown once approved.
            if (j['u'] case final Map<String, dynamic> u) {
              for (final MapEntry(:key, :value) in u.entries) {
                final b = boardOrNull(key);
                if (b == null || !b.proven || value is! int) continue;
                if (!b.plausible(value)) continue;
                final shown = s[key];
                if (shown != null && !b.better(value, shown)) continue;
                if (_legacyAllows(b, e.pubkey, value)) {
                  s[key] = value;
                  proofs.remove(key);
                } else {
                  unchecked[key] = value;
                }
              }
            }
            final name = cleanNameOrNull(j['name']) ?? '';
            latest[e.pubkey] = RemoteScores(
              e.pubkey,
              name.isEmpty
                  ? 'Spieler'
                  : name.substring(0, name.length.clamp(0, 24)),
              s,
              e.createdAt,
              badge: j['k'] == true,
              proofs: proofs,
              unchecked: unchecked,
            );
          } catch (_) {}
        });
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return latest.values.toList();
  }

  /// Values kept from before the check (replaceable in tests).
  @visibleForTesting
  static Map<String, Map<String, int>> legacy = legacyScores;

  /// Results approved by the admins (see [ModerationSync.approve]).
  static Map<String, Map<String, int>> approved = {};

  /// Whether [value] of [author] on a checked board is covered by the
  /// values kept from before the check (see [legacyScores]).
  static bool _legacyAllows(ScoreBoard b, String author, int value) {
    bool covers(int? old) => old != null && !b.better(value, old);
    return covers(legacy[author]?[b.id]) || covers(approved[author]?[b.id]);
  }

  /// Whether [e] counts for the shared rankings when published by [author].
  static bool counts(ScoreBoard b, ScoreEntry e, String author) =>
      !b.proven || e.proof != null || _legacyAllows(b, author, e.value);

  /// The score proven by [proof] for [board] played by [author], or null.
  static int? verify(String board, Map<String, dynamic> proof, String author) =>
      switch (board) {
        'kniffel' => KniffelProof.fromJson(proof)?.verify(author),
        'snake' => SnakeProof.verify(proof, author),
        'klondike' => KlondikeProof.verify(proof, author),
        _ when board.startsWith('mahjong.') => MahjongProof.verify(
          board,
          proof,
          author,
        ),
        _ => null,
      };

  /// Ranking for one board, best first.
  static List<(RemoteScores, int)> rank(ScoreBoard b, List<RemoteScores> all) {
    final list = [
      for (final r in all)
        if (r.scores[b.id] case final v?) (r, v),
    ];
    list.sort(
      (x, y) => x.$2 == y.$2
          ? x.$1.createdAt.compareTo(y.$1.createdAt)
          : (b.better(x.$2, y.$2) ? -1 : 1),
    );
    return list;
  }
}
