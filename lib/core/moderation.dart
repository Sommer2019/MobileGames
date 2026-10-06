import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'nostr/keys.dart';

/// Blocking, banning and reporting players.
///
/// A block only works on this device: messages, invites and friend
/// requests of blocked players are dropped. A ban works the same way, but
/// for everyone: the admins (public keys set at build time with
/// `--dart-define=ADMIN_PUBKEYS=hex,hex`) publish a signed ban list on the
/// relays that every app follows (see [ModerationSync]).
///
/// Reports go encrypted to the admins through the relays. Without admins
/// they go by e-mail (`--dart-define=REPORT_EMAIL=...`), otherwise as a
/// prefilled GitHub issue.
class Moderation extends ChangeNotifier {
  Moderation._();
  static final Moderation I = Moderation._();

  static const _key = 'moderation.blocked';
  static const _bansKey = 'moderation.banned';
  static const reportEmail = String.fromEnvironment('REPORT_EMAIL');
  static const _issues = 'https://github.com/Sommer2019/MobileGames/issues/new';

  /// Public keys (hex) of the players who handle reports and bans.
  static List<String> admins = parseAdmins(
    const String.fromEnvironment('ADMIN_PUBKEYS'),
  );

  static List<String> parseAdmins(String s) => [
    for (final k in s.split(RegExp(r'[,\s]+')))
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(k.toLowerCase())) k.toLowerCase(),
  ];

  static bool isAdmin(String pubkey) => admins.contains(pubkey);

  /// pubkey → name at the time of blocking.
  final Map<String, String> _blocked = {};

  /// Banned by an admin: pubkey → name.
  final Map<String, String> _banned = {};

  Map<String, String> get blocked => Map.unmodifiable(_blocked);
  Map<String, String> get banned => Map.unmodifiable(_banned);

  bool isBanned(String pubkey) =>
      _banned.containsKey(pubkey) && !isAdmin(pubkey);

  /// Blocked here or banned for everyone.
  bool isBlocked(String pubkey) =>
      _blocked.containsKey(pubkey) || isBanned(pubkey);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _blocked.clear();
    for (final e in prefs.getStringList(_key) ?? const <String>[]) {
      final i = e.indexOf(' ');
      if (i == 64) _blocked[e.substring(0, i)] = e.substring(i + 1);
    }
    _banned.clear();
    try {
      final j = jsonDecode(prefs.getString(_bansKey) ?? '{}') as Map;
      for (final e in j.entries) {
        _banned[e.key as String] = e.value as String;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Takes over the current ban list (from the relays).
  Future<void> setBanned(Map<String, String> bans) async {
    if (mapEquals(bans, _banned)) return;
    _banned
      ..clear()
      ..addAll(bans);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bansKey, jsonEncode(_banned));
    notifyListeners();
  }

  Future<void> block(String pubkey, String name) async {
    _blocked[pubkey] = name;
    await _save();
  }

  Future<void> unblock(String pubkey) async {
    _blocked.remove(pubkey);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [
      for (final e in _blocked.entries) '${e.key} ${e.value}',
    ]);
    notifyListeners();
  }

  /// Text of a report about [name] with the [messages] in question.
  static String reportText({
    required String name,
    String? pubkey,
    required List<String> messages,
    String? reason,
  }) {
    final b = StringBuffer()
      ..writeln('Gemeldeter Spieler: $name')
      ..writeln(
        pubkey == null
            ? 'ID: unbekannt'
            : 'ID: ${shortCodeFor(pubkey)} ($pubkey)',
      );
    if (reason != null && reason.isNotEmpty) b.writeln('Grund: $reason');
    b
      ..writeln()
      ..writeln('Nachrichten:');
    for (final m in messages) {
      b.writeln('> $m');
    }
    return b.toString();
  }

  /// Where a report is sent.
  static Uri reportUri(String subject, String body) => reportEmail.isNotEmpty
      ? Uri(
          scheme: 'mailto',
          path: reportEmail,
          query: _query({'subject': subject, 'body': body}),
        )
      : Uri.parse(_issues).replace(
          queryParameters: {
            'title': subject,
            'body': body,
            'labels': 'meldung',
          },
        );

  // mailto needs %20 instead of + for spaces.
  static String _query(Map<String, String> p) => p.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  /// Opens the mail app (or the browser) with the report. False if nothing
  /// could be opened.
  static Future<bool> sendReport(String subject, String body) async {
    try {
      return await launchUrl(
        reportUri(subject, body),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
