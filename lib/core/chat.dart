import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nostr/event.dart';
import 'nostr/keys.dart';
import 'nostr/relay_pool.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.time,
  });

  final String id;
  final bool mine;
  final String text;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mine': mine,
    'text': text,
    't': time.millisecondsSinceEpoch,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    mine: j['mine'] as bool,
    text: j['text'] as String,
    time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
  );
}

/// A non-chat control message sent through the stored DM channel
/// (e.g. friend requests), so it also reaches players who are offline.
class ChatSignal {
  ChatSignal(this.from, this.type, this.name, this.time);
  final String from;
  final String type;
  final String? name;
  final DateTime time;
}

class IncomingChat {
  IncomingChat(this.from, this.senderName, this.message);
  final String from;
  final String? senderName;
  final ChatMessage message;
}

/// Direct messages between players.
///
/// Uses encrypted Nostr direct messages (kind 4, NIP-04). Unlike game
/// signaling these events are stored by the relays, so messages also reach
/// friends who are offline right now; they are fetched on the next start.
class ChatService extends ChangeNotifier {
  ChatService(this.client, this.keys, {SharedPreferences? prefs})
    : _prefsOverride = prefs;

  static const kind = 4;
  static const _maxPerConversation = 300;

  final NostrClient client;
  final KeyPair keys;
  final SharedPreferences? _prefsOverride;
  late SharedPreferences _prefs;

  final Map<String, List<ChatMessage>> _conversations = {};
  final Map<String, int> _unread = {};
  final Map<String, String> _names = {};
  final Set<String> _seenIds = {};
  final _incoming = StreamController<IncomingChat>.broadcast();
  final _signals = StreamController<ChatSignal>.broadcast();
  final List<String> _signalIds = [];
  StreamSubscription<NostrEvent>? _sub;
  int _lastSync = 0;

  /// Conversation currently shown on screen (counts as read).
  String? openConversation;

  Stream<IncomingChat> get incoming => _incoming.stream;

  /// Control messages such as friend requests.
  Stream<ChatSignal> get signals => _signals.stream;

  List<ChatMessage> messages(String pubkey) =>
      List.unmodifiable(_conversations[pubkey] ?? const []);
  int unread(String pubkey) => _unread[pubkey] ?? 0;
  int get totalUnread => _unread.values.fold(0, (a, b) => a + b);

  /// Name a non-friend sent along with their message.
  String? nameOf(String pubkey) => _names[pubkey];

  /// Everybody we have a conversation with, newest first.
  List<String> get conversations {
    final keys = _conversations.keys.toList()
      ..sort(
        (a, b) => _conversations[b]!.last.time.compareTo(
          _conversations[a]!.last.time,
        ),
      );
    return keys;
  }

  Future<void> start() async {
    _prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    _load();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Fetch what arrived while we were offline (at most one week back).
    final since = _lastSync == 0 ? now - 7 * 86400 : _lastSync - 300;
    _sub = client
        .subscribe({
          'kinds': [kind],
          '#p': [keys.publicKey],
          'since': since,
        })
        .listen(_onEvent);
  }

  void _load() {
    _lastSync = _prefs.getInt('chat.lastSync') ?? 0;
    try {
      final data = jsonDecode(_prefs.getString('chat.data') ?? '{}') as Map;
      for (final e in data.entries) {
        final list = [
          for (final m in e.value as List)
            ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
        ];
        _conversations[e.key as String] = list;
        _seenIds.addAll(list.map((m) => m.id));
      }
      final unread = jsonDecode(_prefs.getString('chat.unread') ?? '{}') as Map;
      for (final e in unread.entries) {
        _unread[e.key as String] = e.value as int;
      }
      _signalIds.addAll(_prefs.getStringList('chat.signalIds') ?? const []);
      _seenIds.addAll(_signalIds);
      final names = jsonDecode(_prefs.getString('chat.names') ?? '{}') as Map;
      for (final e in names.entries) {
        _names[e.key as String] = e.value as String;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    await _prefs.setString(
      'chat.data',
      jsonEncode({
        for (final e in _conversations.entries)
          e.key: [for (final m in e.value) m.toJson()],
      }),
    );
    await _prefs.setString('chat.unread', jsonEncode(_unread));
    await _prefs.setString('chat.names', jsonEncode(_names));
    await _prefs.setInt('chat.lastSync', _lastSync);
    await _prefs.setStringList('chat.signalIds', _signalIds);
  }

  void _add(String pubkey, ChatMessage m) {
    final list = _conversations.putIfAbsent(pubkey, () => []);
    list.add(m);
    list.sort((a, b) => a.time.compareTo(b.time));
    if (list.length > _maxPerConversation) list.removeAt(0);
  }

  void _onEvent(NostrEvent e) {
    if (e.pubkey == keys.publicKey || !_seenIds.add(e.id)) return;
    String text;
    String? name;
    try {
      final plain = nip04Decrypt(keys.privateKey, e.pubkey, e.content);
      try {
        final j = jsonDecode(plain);
        if (j is Map && j['mg'] == 1 && j['type'] is String) {
          _signalIds.add(e.id);
          if (_signalIds.length > 500) _signalIds.removeAt(0);
          if (e.createdAt > _lastSync) _lastSync = e.createdAt;
          _save();
          _signals.add(
            ChatSignal(
              e.pubkey,
              j['type'] as String,
              j['name'] as String?,
              DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000),
            ),
          );
          return;
        }
        if (j is Map && j['mg'] == 1) {
          text = j['text'] as String;
          name = j['name'] as String?;
        } else {
          text = plain;
        }
      } on FormatException {
        text = plain;
      }
    } catch (_) {
      return;
    }
    final msg = ChatMessage(
      id: e.id,
      mine: false,
      text: text,
      time: DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000),
    );
    _add(e.pubkey, msg);
    if (name != null) _names[e.pubkey] = name;
    if (openConversation != e.pubkey) {
      _unread[e.pubkey] = unread(e.pubkey) + 1;
    }
    if (e.createdAt > _lastSync) _lastSync = e.createdAt;
    _save();
    notifyListeners();
    _incoming.add(IncomingChat(e.pubkey, name, msg));
  }

  /// Sends a stored control message (see [signals]).
  Future<void> sendSignal(String to, String type, {required String myName}) {
    final content = nip04Encrypt(
      keys.privateKey,
      to,
      jsonEncode({'mg': 1, 'type': type, 'name': myName}),
    );
    final event = NostrEvent.create(
      keys: keys,
      kind: kind,
      content: content,
      tags: [
        ['p', to],
      ],
    );
    _seenIds.add(event.id);
    return client.publish(event);
  }

  Future<void> send(String to, String text, {required String myName}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final content = nip04Encrypt(
      keys.privateKey,
      to,
      jsonEncode({'mg': 1, 'text': t, 'name': myName}),
    );
    final event = NostrEvent.create(
      keys: keys,
      kind: kind,
      content: content,
      tags: [
        ['p', to],
      ],
    );
    _seenIds.add(event.id);
    _add(
      to,
      ChatMessage(id: event.id, mine: true, text: t, time: DateTime.now()),
    );
    notifyListeners();
    await _save();
    await client.publish(event);
  }

  void markRead(String pubkey) {
    if (_unread.remove(pubkey) != null) {
      _save();
      notifyListeners();
    }
  }

  void deleteConversation(String pubkey) {
    _conversations.remove(pubkey);
    _unread.remove(pubkey);
    _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
