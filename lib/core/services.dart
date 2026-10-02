import 'dart:async';

import 'account.dart';
import 'chat.dart';
import 'friend_codes.dart';
import 'friend_requests.dart';
import 'leaderboard.dart';
import 'secrets.dart';
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
    friendCodes = FriendCodes(client, account.keys);
    friendRequests = FriendRequests(account, chat, codes: friendCodes);
    friendCodes.publish(account.name);
    leaderboard = Leaderboard(client, account);
    Leaderboard.instance = leaderboard;
    leaderboard.publish();
    // Show the 🎮 badge to friends as soon as the code was found.
    var badge = Secrets.I.unlocked;
    Secrets.I.addListener(() {
      if (Secrets.I.unlocked == badge) return;
      badge = Secrets.I.unlocked;
      presence.announce();
      leaderboard.publish();
    });
    var lastName = account.name;
    account.addListener(() {
      if (account.name != lastName) {
        lastName = account.name;
        friendCodes.publish(account.name);
        leaderboard.publish();
      }
    });
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
  late final FriendCodes friendCodes;
  late final Leaderboard leaderboard;

  GameSession createSession(MatchInfo match) =>
      GameSession(match, messenger, p2p: p2pFactory());
}
