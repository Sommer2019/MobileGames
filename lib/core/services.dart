import 'dart:async';

import 'account.dart';
import 'account_transfer.dart';
import 'chat.dart';
import 'device_identity.dart';
import 'friend_codes.dart';
import 'friend_requests.dart';
import 'leaderboard.dart';
import 'moderation.dart';
import 'moderation_sync.dart';
import 'profile_backup.dart';
import 'secrets.dart';
import 'net/game_session.dart';
import 'net/matchmaker.dart';
import 'net/messenger.dart';
import 'net/spectate.dart';
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
       p2pFactory =
           p2pFactory ?? (webRtcUsable() ? WebRtcTransport.new : null) {
    messenger.start();
    matchmaker = Matchmaker(messenger, nameProvider: () => account.name);
    spectators = SpectatorHub(messenger, account, createSession);
    presence = Presence(client, account, playing: spectators.playing)..start();
    chat = ChatService(client, account.keys);
    friendCodes = FriendCodes(client, account.keys);
    friendRequests = FriendRequests(account, chat, codes: friendCodes);
    friendCodes.publish(account.name);
    profileBackup = ProfileBackup(client, account);
    leaderboard = Leaderboard(client, account);
    Leaderboard.instance = leaderboard;
    leaderboard.publish();
    moderation = ModerationSync(client, account.keys);
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
    await Moderation.I.load();
    final client = RelayPool();
    // After a reinstall the device key may point to an account that was
    // taken over from another phone (see [AccountTransfer]).
    final account = await Account.load(
      recover: () async {
        final key = await DeviceIdentity.recover();
        if (key == null || await DeviceIdentity.androidKey() != key) {
          return key;
        }
        return AccountTransfer.resolve(client, key);
      },
    );
    final s = Services(account: account, client: client);
    _instance = s;
    await s.friendRequests.start();
    unawaited(s._restoreProfile());
    await s.chat.start();
    await s.moderation.start();
    return s;
  }

  final Account account;
  final NostrClient client;
  final Messenger messenger;

  /// Direct connections; null when WebRTC cannot run here (then all game
  /// messages go over the encrypted relays).
  final P2pTransport Function()? p2pFactory;
  late final Matchmaker matchmaker;
  late final Presence presence;
  late final SpectatorHub spectators;
  late final ChatService chat;
  late final FriendRequests friendRequests;
  late final FriendCodes friendCodes;
  late final Leaderboard leaderboard;
  late final ProfileBackup profileBackup;
  late final ModerationSync moderation;

  /// Brings back name and friends after a reinstall, then keeps the backup
  /// up to date. Saving only starts afterwards so an empty fresh profile
  /// never overwrites the backup.
  Future<void> _restoreProfile() async {
    final changed = await profileBackup.restore();
    account.addListener(profileBackup.schedule);
    if (changed || account.friends.isNotEmpty) profileBackup.schedule();
  }

  GameSession createSession(MatchInfo match) =>
      GameSession(match, messenger, p2p: p2pFactory?.call());
}
