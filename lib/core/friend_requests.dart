import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'chat.dart';
import 'nostr/keys.dart';

/// Friendships in both directions: adding somebody sends them a request;
/// when they accept, each one is in the other's friend list.
class FriendRequests extends ChangeNotifier {
  FriendRequests(this.account, this.chat, {SharedPreferences? prefs})
    : _prefsOverride = prefs;

  final Account account;
  final ChatService chat;
  final SharedPreferences? _prefsOverride;
  late SharedPreferences _prefs;
  StreamSubscription<ChatSignal>? _sub;

  /// Incoming requests: public key -> name.
  final Map<String, String> pending = {};
  final Set<String> _declined = {};
  final _incoming = StreamController<String>.broadcast();
  final _accepted = StreamController<String>.broadcast();

  /// Public keys of new incoming requests (for popups).
  Stream<String> get incoming => _incoming.stream;

  /// Public keys of friends that accepted our request.
  Stream<String> get accepted => _accepted.stream;

  Future<void> start() async {
    _prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    try {
      final p = jsonDecode(_prefs.getString('friends.pending') ?? '{}') as Map;
      p.forEach((k, v) => pending[k as String] = v as String);
      _declined.addAll(_prefs.getStringList('friends.declined') ?? const []);
    } catch (_) {}
    _sub = chat.signals.listen(_onSignal);
  }

  Future<void> _save() async {
    await _prefs.setString('friends.pending', jsonEncode(pending));
    await _prefs.setStringList('friends.declined', _declined.toList());
    notifyListeners();
  }

  void _onSignal(ChatSignal s) {
    switch (s.type) {
      case 'friend-request':
        if (account.friend(s.from) != null) {
          // Already friends: just confirm, so the other side knows.
          if (s.name != null) account.updateFriendName(s.from, s.name!);
          chat.sendSignal(s.from, 'friend-accept', myName: account.name);
          return;
        }
        if (_declined.contains(s.from) || pending.containsKey(s.from)) return;
        pending[s.from] = s.name ?? 'Unbekannt';
        _save();
        _incoming.add(s.from);
      case 'friend-accept':
        if (account.friend(s.from) == null) {
          account.addFriend(s.from, name: s.name);
        } else if (s.name != null) {
          account.updateFriendName(s.from, s.name!);
        }
        pending.remove(s.from);
        _save();
        _accepted.add(s.from);
      case 'friend-remove':
        pending.remove(s.from);
        _save();
    }
  }

  /// Adds a friend by code and sends them a friend request.
  Future<String?> addByCode(String code, {String? name}) async {
    final error = await account.addFriend(code, name: name);
    if (error != null) return error;
    final pub = parseFriendCode(code)!;
    _declined.remove(pub);
    // If they asked us before, this is an acceptance.
    final type = pending.remove(pub) != null
        ? 'friend-accept'
        : 'friend-request';
    await _save();
    await chat.sendSignal(pub, type, myName: account.name);
    return null;
  }

  Future<void> acceptRequest(String pubkey) async {
    final name = pending.remove(pubkey);
    if (account.friend(pubkey) == null) {
      await account.addFriend(pubkey, name: name);
    }
    await _save();
    await chat.sendSignal(pubkey, 'friend-accept', myName: account.name);
  }

  Future<void> declineRequest(String pubkey) async {
    pending.remove(pubkey);
    _declined.add(pubkey);
    await _save();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
