import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity.dart';
import 'names.dart';
import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';
import 'net/messenger.dart';
import 'secrets.dart';

class Friend {
  Friend(this.pubkey, this.name);
  final String pubkey;
  String name;

  Map<String, String> toJson() => {'pubkey': pubkey, 'name': name};
  factory Friend.fromJson(Map<String, dynamic> j) =>
      Friend(j['pubkey'] as String, cleanNameOrNull(j['name']) ?? 'Freund');
}

/// Local, serverless account: a key pair stored on the device, a display
/// name and a friend list. The public key (as "npub" code) is the friend code.
class Account extends ChangeNotifier {
  Account._(this._prefs, this.keys, this._name, this.friends, this._prefix);

  final String _prefix;
  String get _keyName => '$_prefix.name';
  String get _keyFriends => '$_prefix.friends';

  final SharedPreferences _prefs;
  final KeyPair keys;
  String _name;
  final List<Friend> friends;

  /// Loads (or creates) the account. [prefix] separates the storage keys
  /// (used by tests that simulate several players on one device).
  /// [recover] supplies the key of an earlier installation on this device
  /// (default: [DeviceIdentity.recover]).
  static Future<Account> load({
    String prefix = 'account',
    Future<String?> Function()? recover,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var priv = prefs.getString('$prefix.privateKey');
    if (priv == null) {
      // After a reinstall: the same account again, if the device allows.
      priv = _validKey(await (recover ?? DeviceIdentity.recover)());
      priv ??= KeyPair.generate().privateKey;
      await prefs.setString('$prefix.privateKey', priv);
    }
    await DeviceIdentity.remember(priv);
    final keys = KeyPair(priv);
    final name =
        cleanNameOrNull(prefs.getString('$prefix.name')) ??
        'Spieler ${keys.publicKey.substring(0, 4)}';
    final friends = <Friend>[];
    try {
      for (final f
          in jsonDecode(prefs.getString('$prefix.friends') ?? '[]') as List) {
        friends.add(Friend.fromJson(Map<String, dynamic>.from(f as Map)));
      }
    } catch (_) {}
    return Account._(prefs, keys, name, friends, prefix);
  }

  static String? _validKey(String? key) {
    if (key == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) return null;
    try {
      KeyPair(key);
      return key;
    } catch (_) {
      return null;
    }
  }

  String get name => _name;

  /// Full code (npub), used in QR codes.
  String get friendCode => pubKeyToNpub(keys.publicKey);

  /// Short code to type in, e.g. "K7Q2M-9XW4P".
  String get shortCode => formatShortCode(shortCodeFor(keys.publicKey));

  /// Content of the QR code.
  String get qrPayload =>
      'mobilegames://friend/$friendCode?name=${Uri.encodeComponent(name)}';

  Future<void> setName(String value) async {
    final v = cleanName(value);
    if (v.isEmpty) return;
    _name = v;
    await _prefs.setString(_keyName, _name);
    notifyListeners();
  }

  Friend? friend(String pubkey) {
    for (final f in friends) {
      if (f.pubkey == pubkey) return f;
    }
    return null;
  }

  /// Adds a friend by code. Returns an error message or null on success.
  Future<String?> addFriend(String code, {String? name}) async {
    final pub = parseFriendCode(code);
    if (pub == null) return 'Ungültiger Freundescode';
    if (pub == keys.publicKey) return 'Das ist dein eigener Code';
    if (friend(pub) != null) return 'Ist schon in deiner Freundesliste';
    friends.add(
      Friend(pub, cleanNameOrNull(name) ?? 'Freund ${pub.substring(0, 4)}'),
    );
    await _save();
    return null;
  }

  Future<void> removeFriend(String pubkey) async {
    friends.removeWhere((f) => f.pubkey == pubkey);
    await _save();
  }

  Future<void> updateFriendName(String pubkey, String name) async {
    final f = friend(pubkey);
    final clean = cleanName(name);
    if (f == null || f.name == clean || clean.isEmpty) return;
    f.name = clean;
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _keyFriends,
      jsonEncode(friends.map((f) => f.toJson()).toList()),
    );
    notifyListeners();
  }
}

/// Online status of friends: every client periodically broadcasts a small
/// signed presence event; friends listen for the authors they know.
class Presence extends ChangeNotifier {
  Presence(
    this.client,
    this.account, {
    this.interval = const Duration(seconds: 30),
  });

  final NostrClient client;
  final Account account;
  final Duration interval;
  final Map<String, DateTime> _lastSeen = {};
  Timer? _timer;
  StreamSubscription<NostrEvent>? _sub;
  List<String> _watched = const [];

  final Set<String> _badges = {};

  /// Whether the friend found the Konami code (shows 🎮 next to the name).
  bool hasBadge(String pubkey) => _badges.contains(pubkey);

  /// When the last presence of [pubkey] arrived (this session).
  DateTime? lastSeen(String pubkey) => _lastSeen[pubkey];

  bool isOnline(String pubkey) {
    final t = _lastSeen[pubkey];
    return t != null && DateTime.now().difference(t) < interval * 2.5;
  }

  void start() {
    _announce();
    _timer = Timer.periodic(interval, (_) {
      _announce();
      notifyListeners();
    });
    account.addListener(_resubscribe);
    _resubscribe();
  }

  /// Publishes our online status now.
  void announce() => _announce();

  void _announce() {
    client.publish(
      NostrEvent.create(
        keys: account.keys,
        kind: Kinds.presence,
        content: jsonEncode({
          'name': account.name,
          if (Secrets.I.unlocked) 'k': true,
        }),
        tags: [
          ['t', 'mobilegames-presence'],
        ],
      ),
    );
  }

  void _resubscribe() {
    final authors = account.friends.map((f) => f.pubkey).toList()..sort();
    if (listEquals(authors, _watched)) return;
    _watched = authors;
    _sub?.cancel();
    _sub = null;
    if (authors.isEmpty) return;
    _sub = client
        .subscribe({
          'kinds': [Kinds.presence],
          'authors': authors,
          'since': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 90,
        })
        .listen((e) {
          _lastSeen[e.pubkey] = DateTime.now();
          try {
            final j = jsonDecode(e.content) as Map;
            final name = j['name'];
            if (name is String) account.updateFriendName(e.pubkey, name);
            if (j['k'] == true) {
              _badges.add(e.pubkey);
            } else {
              _badges.remove(e.pubkey);
            }
          } catch (_) {}
          notifyListeners();
        });
    // Announce again so newly added friends see us quickly.
    _announce();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    account.removeListener(_resubscribe);
    super.dispose();
  }
}
