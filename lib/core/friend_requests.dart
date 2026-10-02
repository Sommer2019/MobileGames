import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'chat.dart';
import 'friend_codes.dart';
import 'nostr/keys.dart';

/// Friendships in both directions: adding somebody sends them a request;
/// when they accept, each one is in the other's friend list.
class FriendRequests extends ChangeNotifier {
  FriendRequests(
    this.account,
    this.chat, {
    this.codes,
    SharedPreferences? prefs,
  }) : _prefsOverride = prefs;

  final Account account;
  final ChatService chat;

  /// Resolves short friend codes (optional, e.g. not needed in tests).
  final FriendCodes? codes;
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

  /// Turns any accepted input (npub, hex key, QR link, short code) into a
  /// public key. Returns (public key, name) or an error message.
  Future<((String, String?)?, String?)> resolveInput(String input) async {
    // QR links look like mobilegames://friend/npub1...?name=Anna
    final npub = RegExp(r'npub1[02-9ac-hj-np-z]+').firstMatch(input)?.group(0);
    String? qrName;
    final nameMatch = RegExp(r'[?&]name=([^&]+)').firstMatch(input);
    if (nameMatch != null) qrName = Uri.decodeComponent(nameMatch.group(1)!);
    final direct = parseFriendCode(npub ?? input);
    if (direct != null) return ((direct, qrName), null);
    final short = parseShortCode(input);
    if (short == null) return (null, 'Ungültiger Freundescode');
    if (short == shortCodeFor(account.keys.publicKey)) {
      return (null, 'Das ist dein eigener Code');
    }
    final resolved = await codes?.resolve(short);
    if (resolved == null) {
      return (
        null,
        'Code nicht gefunden. Dein Freund muss online sein oder die App '
            'kürzlich geöffnet haben.',
      );
    }
    return (resolved, null);
  }

  /// Adds a friend by code and sends them a friend request.
  Future<String?> addByCode(String code, {String? name}) async {
    final (found, problem) = await resolveInput(code);
    if (found == null) return problem;
    final (pub, foundName) = found;
    final error = await account.addFriend(pub, name: name ?? foundName);
    if (error != null) return error;
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
