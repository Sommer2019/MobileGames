import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';
import 'net/messenger.dart';

class Friend {
  Friend(this.pubkey, this.name);
  final String pubkey;
  String name;

  Map<String, String> toJson() => {'pubkey': pubkey, 'name': name};
  factory Friend.fromJson(Map<String, dynamic> j) =>
      Friend(j['pubkey'] as String, j['name'] as String? ?? 'Freund');
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
  static Future<Account> load({String prefix = 'account'}) async {
    final prefs = await SharedPreferences.getInstance();
    var priv = prefs.getString('$prefix.privateKey');
    if (priv == null) {
      priv = KeyPair.generate().privateKey;
      await prefs.setString('$prefix.privateKey', priv);
    }
    final keys = KeyPair(priv);
    final name =
        prefs.getString('$prefix.name') ??
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

  String get name => _name;
  String get friendCode => pubKeyToNpub(keys.publicKey);

  Future<void> setName(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    _name = v.length > 24 ? v.substring(0, 24) : v;
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
    friends.add(Friend(pub, name ?? 'Freund ${pub.substring(0, 4)}'));
    await _save();
    return null;
  }

  Future<void> removeFriend(String pubkey) async {
    friends.removeWhere((f) => f.pubkey == pubkey);
    await _save();
  }

  Future<void> updateFriendName(String pubkey, String name) async {
    final f = friend(pubkey);
    if (f == null || f.name == name || name.trim().isEmpty) return;
    f.name = name.trim();
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

  void _announce() {
    client.publish(
      NostrEvent.create(
        keys: account.keys,
        kind: Kinds.presence,
        content: jsonEncode({'name': account.name}),
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
            final name = (jsonDecode(e.content) as Map)['name'];
            if (name is String) account.updateFriendName(e.pubkey, name);
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
