import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'leaderboard.dart';
import 'moderation.dart';
import 'names.dart';
import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';

/// A report about a player, as the admins see it.
class Report {
  Report({
    required this.id,
    required this.from,
    required this.fromName,
    required this.pubkey,
    required this.name,
    required this.reason,
    required this.messages,
    required this.time,
  });

  final String id;
  final String from;
  final String fromName;

  /// The reported player (null if the app did not know the key).
  final String? pubkey;
  final String name;
  final String reason;
  final List<String> messages;
  final DateTime time;
}

/// Ban list and reports over the relays (NIP-78 app data, kind 30078).
///
/// Each admin publishes one replaceable, signed ban list; every app follows
/// the lists of the admins built into it and drops banned players like
/// blocked ones. Reports are separate events, encrypted (NIP-44) for one
/// admin each, so only that admin can read them.
class ModerationSync extends ChangeNotifier {
  ModerationSync(this.client, this.keys, {List<String>? admins})
    : admins = admins ?? Moderation.admins;

  static const kind = 30078;
  static const _bansD = 'mobilegames-bans';
  static const _approvedD = 'mobilegames-approved';
  static const _reportD = 'mobilegames-report-';
  static const _doneKey = 'moderation.reportsDone';

  final NostrClient client;
  final KeyPair keys;
  final List<String> admins;

  StreamSubscription<NostrEvent>? _bansSub;
  StreamSubscription<NostrEvent>? _reportsSub;

  /// Latest ban list per admin: author → (created at, pubkey → name).
  final Map<String, (int, Map<String, String>)> _lists = {};

  /// Latest list of approved results per admin: author → (created at,
  /// pubkey → board → value). See [approve].
  final Map<String, (int, Map<String, Map<String, int>>)> _approved = {};

  final Map<String, Report> _reports = {};
  final Set<String> _done = {};

  bool get isAdmin => admins.contains(keys.publicKey);

  /// Open reports, newest first. Reports about banned players are done.
  List<Report> get openReports {
    final list = [
      for (final r in _reports.values)
        if (!_done.contains(r.id) &&
            (r.pubkey == null || !Moderation.I.isBanned(r.pubkey!)))
          r,
    ]..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  /// Our own ban list (as admin).
  Map<String, String> get myBans =>
      Map.of(_lists[keys.publicKey]?.$2 ?? const {});

  Future<void> start() async {
    if (admins.isEmpty) return;
    _bansSub = client
        .subscribe({
          'kinds': [kind],
          'authors': admins,
          '#d': [_bansD, _approvedD],
        })
        .listen((e) => _d(e) == _approvedD ? _onApproved(e) : _onBans(e));
    if (!isAdmin) return;
    final prefs = await SharedPreferences.getInstance();
    _done.addAll(prefs.getStringList(_doneKey) ?? const []);
    final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 90 * 86400;
    _reportsSub = client
        .subscribe({
          'kinds': [kind],
          '#p': [keys.publicKey],
          'since': since,
        })
        .listen(_onReport);
  }

  static String? _d(NostrEvent e) =>
      e.tags.where((t) => t.length > 1 && t[0] == 'd').firstOrNull?[1];

  void _onBans(NostrEvent e) {
    if (!admins.contains(e.pubkey) || _d(e) != _bansD) return;
    final prev = _lists[e.pubkey];
    if (prev != null && prev.$1 >= e.createdAt) return;
    final bans = <String, String>{};
    try {
      final j = jsonDecode(e.content) as Map<String, dynamic>;
      for (final MapEntry(:key, :value)
          in (j['b'] as Map<String, dynamic>).entries) {
        if (RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
          bans[key] = cleanNameOrNull(value) ?? 'Spieler';
        }
      }
    } catch (_) {
      return;
    }
    _lists[e.pubkey] = (e.createdAt, bans);
    Moderation.I.setBanned({for (final l in _lists.values) ...l.$2});
    notifyListeners();
  }

  void _onApproved(NostrEvent e) {
    if (!admins.contains(e.pubkey) || _d(e) != _approvedD) return;
    final prev = _approved[e.pubkey];
    if (prev != null && prev.$1 >= e.createdAt) return;
    final list = <String, Map<String, int>>{};
    try {
      final j = jsonDecode(e.content) as Map<String, dynamic>;
      for (final MapEntry(:key, :value)
          in (j['a'] as Map<String, dynamic>).entries) {
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) continue;
        list[key] = {
          for (final MapEntry(key: board, value: v)
              in (value as Map<String, dynamic>).entries)
            if (v is int) board: v,
        };
      }
    } catch (_) {
      return;
    }
    _approved[e.pubkey] = (e.createdAt, list);
    Leaderboard.approved = _mergedApproved();
    notifyListeners();
  }

  /// All admins' approvals together; per board the best approved value.
  Map<String, Map<String, int>> _mergedApproved() {
    final all = <String, Map<String, int>>{};
    for (final (_, list) in _approved.values) {
      for (final MapEntry(key: pubkey, value: boards) in list.entries) {
        final mine = all.putIfAbsent(pubkey, () => {});
        for (final MapEntry(key: board, :value) in boards.entries) {
          final b = boardOrNull(board);
          final old = mine[board];
          if (b != null && (old == null || b.better(value, old))) {
            mine[board] = value;
          }
        }
      }
    }
    return all;
  }

  /// Our own approvals (as admin).
  Map<String, Map<String, int>> get myApprovals => {
    for (final MapEntry(:key, :value)
        in (_approved[keys.publicKey]?.$2 ?? const {}).entries)
      key: Map.of(value),
  };

  /// Lets a result without a recorded game count (admins only): from now
  /// on [value] and anything not better of [pubkey] on [board] is shown,
  /// e.g. the best values from before results were checked.
  Future<void> approve(String pubkey, String board, int value) async {
    if (!isAdmin) return;
    final list = myApprovals;
    list.putIfAbsent(pubkey, () => {})[board] = value;
    final last = _approved[keys.publicKey]?.$1 ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final event = NostrEvent.create(
      keys: keys,
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (now > last ? now : last + 1) * 1000,
      ),
      content: jsonEncode({'a': list}),
      tags: const [
        ['d', _approvedD],
      ],
    );
    _onApproved(event);
    await client.publish(event);
  }

  void _onReport(NostrEvent e) {
    final d = _d(e);
    if (d == null || !d.startsWith(_reportD) || _reports.containsKey(e.id)) {
      return;
    }
    try {
      final j = jsonDecode(
        nip44Decrypt(keys.privateKey, e.pubkey, e.content),
      ) as Map<String, dynamic>;
      final pubkey = j['pubkey'];
      _reports[e.id] = Report(
        id: e.id,
        from: e.pubkey,
        fromName: cleanNameOrNull(j['from']) ?? 'Spieler',
        pubkey: pubkey is String && pubkey.length == 64 ? pubkey : null,
        name: cleanNameOrNull(j['name']) ?? 'Spieler',
        reason: (j['reason'] as String? ?? '').trim(),
        messages: [for (final m in j['messages'] as List? ?? const []) '$m'],
        time: DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000),
      );
      notifyListeners();
    } catch (_) {
      // Not for us or corrupted.
    }
  }

  /// Sends a report to every admin. False if there is no admin.
  Future<bool> report({
    required String name,
    String? pubkey,
    required List<String> messages,
    String reason = '',
    required String myName,
  }) async {
    if (admins.isEmpty) return false;
    final plain = jsonEncode({
      'pubkey': pubkey,
      'name': name,
      'reason': reason,
      'messages': messages.take(20).toList(),
      'from': myName,
    });
    for (final admin in admins) {
      await client.publish(
        NostrEvent.create(
          keys: keys,
          kind: kind,
          content: nip44Encrypt(keys.privateKey, admin, plain),
          tags: [
            ['d', '$_reportD${randomHex(8)}'],
            ['p', admin],
          ],
        ),
      );
    }
    return true;
  }

  /// Marks a report as handled (only on this device).
  Future<void> dismiss(Report r) async {
    _done.add(r.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_doneKey, _done.toList());
    notifyListeners();
  }

  /// Bans or unbans [pubkey] for everyone (admins only).
  Future<void> setBan(
    String pubkey,
    String name, {
    required bool banned,
  }) async {
    if (!isAdmin) return;
    final bans = myBans;
    if (banned) {
      bans[pubkey] = name;
    } else {
      bans.remove(pubkey);
    }
    // Strictly newer than the last list, even within the same second.
    final last = _lists[keys.publicKey]?.$1 ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final event = NostrEvent.create(
      keys: keys,
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (now > last ? now : last + 1) * 1000,
      ),
      content: jsonEncode({'b': bans}),
      tags: const [
        ['d', _bansD],
      ],
    );
    // Take it over right away, the relays echo it later.
    _onBans(event);
    await client.publish(event);
  }

  @override
  void dispose() {
    _bansSub?.cancel();
    _reportsSub?.cancel();
    super.dispose();
  }
}
