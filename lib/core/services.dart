import 'dart:async';

import 'account.dart';
import 'chat.dart';
import 'friend_requests.dart';
import 'notifications.dart';
import 'net/game_session.dart';
import 'net/matchmaker.dart';
import 'net/messenger.dart';
import 'net/webrtc_transport.dart';
import 'nostr/relay_pool.dart';

/// App wide singletons. There is no own server: everything runs on the
/// device and talks to public Nostr relays and directly to other players.
class Services {
  Services({
    required this.account,
    required this.client,
    P2pTransport Function()? p2pFactory,
  }) : messenger = Messenger(client, account.keys),
       p2pFactory = p2pFactory ?? WebRtcTransport.new {
    messenger.start();
    matchmaker = Matchmaker(messenger, nameProvider: () => account.name);
    presence = Presence(client, account)..start();
    chat = ChatService(client, account.keys);
    friendRequests = FriendRequests(account, chat);
  }

  static Services? _instance;
  static Services get I => _instance!;
  static bool get isReady => _instance != null;
  static set instance(Services s) => _instance = s;

  static Future<Services> init() async {
    final account = await Account.load();
    final s = Services(account: account, client: RelayPool());
    _instance = s;
    await s.friendRequests.start();
    await s.chat.start();
    unawaited(Notifications.I.init());
    return s;
  }

  final Account account;
  final NostrClient client;
  final Messenger messenger;
  final P2pTransport Function() p2pFactory;
  late final Matchmaker matchmaker;
  late final Presence presence;
  late final ChatService chat;
  late final FriendRequests friendRequests;

  GameSession createSession(MatchInfo match) =>
      GameSession(match, messenger, p2p: p2pFactory());
}
