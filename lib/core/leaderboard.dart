import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
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
  });

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
  ),
  ScoreBoard(
    'klondike',
    'klondike',
    'Solitär',
    'Punkte',
    max: 40000,
    legacyKey: 'klondike.best',
  ),
  ScoreBoard('kniffel', 'yahtzee', 'Würfelkönig allein', 'Punkte', max: 1575),
  ScoreBoard(
    'mahjong.tower',
    'mahjong',
    'Mahjong Pyramide',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
  ),
  ScoreBoard(
    'mahjong.pyramid',
    'mahjong',
    'Mahjong Breit',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
  ),
  ScoreBoard(
    'mahjong.turm',
    'mahjong',
    'Mahjong Turm',
    's',
    lowerIsBetter: true,
    min: 10,
    time: true,
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

/// A result in the personal list.
class ScoreEntry {
  ScoreEntry(this.value, this.at);
  final int value;
  final DateTime at;

  Map<String, int> toJson() => {'v': value, 't': at.millisecondsSinceEpoch};
  factory ScoreEntry.fromJson(Map<String, dynamic> j) => ScoreEntry(
    j['v'] as int,
    DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
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
  });
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
  static Future<bool> submit(String id, int value, {DateTime? at}) async {
    final b = boardById(id);
    if (!b.plausible(value)) return false;
    final prefs = await SharedPreferences.getInstance();
    final list = _history(prefs, b);
    final record = list.isEmpty || b.better(value, list.first.value);
    list
      ..add(ScoreEntry(value, at ?? DateTime.now()))
      ..sort(
        (x, y) => x.value == y.value
            ? x.at.compareTo(y.at)
            : (b.better(x.value, y.value) ? -1 : 1),
      );
    if (list.length > keep) list.removeRange(keep, list.length);
    await prefs.setString(_key(id), jsonEncode(list));
    if (record) unawaited(instance?.publish());
    return record;
  }

  // --------------------------------------------------------------- shared

  /// Publishes our best values (replaces the previous event).
  Future<void> publish() async {
    final scores = await bests();
    if (scores.isEmpty) return;
    await client.publish(
      NostrEvent.create(
        keys: account.keys,
        kind: kind,
        content: jsonEncode({
          'name': account.name,
          's': scores,
          if (Secrets.I.unlocked) 'k': true,
        }),
        tags: [
          ['d', _d],
          ['t', _t],
        ],
      ),
    );
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
            for (final MapEntry(:key, :value)
                in (j['s'] as Map<String, dynamic>).entries) {
              final b = boards.where((b) => b.id == key).firstOrNull;
              if (b != null && value is int && b.plausible(value)) {
                s[key] = value;
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
            );
          } catch (_) {}
        });
    await Future<void>.delayed(timeout);
    await sub.cancel();
    return latest.values.toList();
  }

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
