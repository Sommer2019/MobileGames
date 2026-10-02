import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/net/game_session.dart';
import 'package:mobile_games/core/net/matchmaker.dart';
import 'package:mobile_games/core/net/messenger.dart';
import 'package:mobile_games/core/nostr/keys.dart';

import 'fake_nostr.dart';

class Player {
  Player(FakeRelayBus bus, this.name)
    : messenger = Messenger(bus.client(), KeyPair.generate()) {
    messenger.start();
    matchmaker = Matchmaker(
      messenger,
      nameProvider: () => name,
      seekInterval: const Duration(milliseconds: 50),
      handshakeTimeout: const Duration(milliseconds: 500),
      inviteTimeout: const Duration(seconds: 2),
    );
  }

  final String name;
  final Messenger messenger;
  late final Matchmaker matchmaker;
  String get pub => messenger.me;
}

/// Simulates a WebRTC data channel between two transports.
class FakeP2p implements P2pTransport {
  FakeP2p? peer;
  final _incoming = StreamController<String>.broadcast();
  final _open = StreamController<bool>.broadcast();
  bool _isOpen = false;
  final List<Map<String, dynamic>> signals = [];
  late void Function(Map<String, dynamic>) _send;

  @override
  Stream<String> get incoming => _incoming.stream;
  @override
  Stream<bool> get openChanges => _open.stream;
  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> start({
    required bool isHost,
    required void Function(Map<String, dynamic>) sendSignal,
  }) async {
    _send = sendSignal;
    if (isHost) _send({'kind': 'sdp', 'type': 'offer'});
  }

  @override
  Future<void> onSignal(Map<String, dynamic> s) async {
    signals.add(s);
    if (s['type'] == 'offer') {
      _send({'kind': 'sdp', 'type': 'answer'});
      _setOpen();
      peer!._setOpen();
    }
  }

  void _setOpen() {
    _isOpen = true;
    _open.add(true);
  }

  @override
  void send(String text) => peer!._incoming.add(text);

  @override
  Future<void> close() async => _isOpen = false;
}

Future<void> pump([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('two random seekers get matched with exactly one host', () async {
    final bus = FakeRelayBus();
    final a = Player(bus, 'Anna'), b = Player(bus, 'Ben');
    final results = await Future.wait([
      a.matchmaker.findRandom('chess'),
      b.matchmaker.findRandom('chess'),
    ]).timeout(const Duration(seconds: 5));
    expect(results[0].matchId, results[1].matchId);
    expect(results[0].opponent, b.pub);
    expect(results[1].opponent, a.pub);
    expect(results[0].opponentName, 'Ben');
    expect(results[1].opponentName, 'Anna');
    expect(results[0].isHost != results[1].isHost, isTrue);
  });

  test('seekers for different games are not matched; cancel works', () async {
    final bus = FakeRelayBus();
    final a = Player(bus, 'A'), b = Player(bus, 'B');
    final fa = a.matchmaker.findRandom('chess');
    final fb = b.matchmaker.findRandom('connect_four');
    var matched = false;
    for (final f in [fa, fb]) {
      f.then((_) => matched = true).catchError((_) => false);
    }
    await pump(400);
    expect(matched, isFalse);
    a.matchmaker.cancelRandom();
    b.matchmaker.cancelRandom();
    await expectLater(fa, throwsA(isA<MatchmakingCancelled>()));
    await expectLater(fb, throwsA(isA<MatchmakingCancelled>()));
  });

  test('four seekers form two distinct pairs', () async {
    final bus = FakeRelayBus();
    final players = [for (var i = 0; i < 4; i++) Player(bus, 'P$i')];
    final results = await Future.wait(
      players.map((p) => p.matchmaker.findRandom('battleship')),
    ).timeout(const Duration(seconds: 10));
    for (var i = 0; i < 4; i++) {
      final opp = players.indexWhere((p) => p.pub == results[i].opponent);
      expect(
        results[opp].opponent,
        players[i].pub,
        reason: 'pairing is mutual',
      );
      expect(results[opp].matchId, results[i].matchId);
    }
  });

  test('friend invite accepted', () async {
    final bus = FakeRelayBus();
    final a = Player(bus, 'Anna'), b = Player(bus, 'Ben');
    b.matchmaker.invites.listen((inv) async {
      expect(inv.fromName, 'Anna');
      expect(inv.gameId, 'yahtzee');
      final info = await b.matchmaker.acceptInvite(inv);
      expect(info, isNotNull);
      expect(info!.isHost, isFalse);
      expect(info.gameId, 'yahtzee');
    });
    final info = await a.matchmaker.inviteFriend(b.pub, 'Ben', 'yahtzee');
    expect(info, isNotNull);
    expect(info!.isHost, isTrue);
    expect(info.opponentName, 'Ben');
    await pump();
  });

  test('friend invite declined and cancelled', () async {
    final bus = FakeRelayBus();
    final a = Player(bus, 'Anna'), b = Player(bus, 'Ben');
    final sub = b.matchmaker.invites.listen(b.matchmaker.declineInvite);
    expect(await a.matchmaker.inviteFriend(b.pub, 'Ben', 'chess'), isNull);
    await sub.cancel();

    final cancelled = <String>[];
    b.matchmaker.cancelledInvites.listen(cancelled.add);
    final completer = Completer<IncomingInvite>();
    b.matchmaker.invites.listen(completer.complete);
    final pending = a.matchmaker.inviteFriend(b.pub, 'Ben', 'chess');
    final inv = await completer.future;
    a.matchmaker.cancelInvite(inv.matchId);
    expect(await pending, isNull);
    await pump();
    expect(cancelled, [inv.matchId]);
  });

  Future<(GameSession, GameSession)> connect(
    FakeRelayBus bus, {
    bool withP2p = false,
  }) async {
    final a = Player(bus, 'A'), b = Player(bus, 'B');
    final r = await Future.wait([
      a.matchmaker.findRandom('x'),
      b.matchmaker.findRandom('x'),
    ]);
    FakeP2p? pa, pb;
    if (withP2p) {
      pa = FakeP2p();
      pb = FakeP2p();
      pa.peer = pb;
      pb.peer = pa;
    }
    final sa = GameSession(
      r[0],
      a.messenger,
      p2p: pa,
      helloInterval: const Duration(milliseconds: 50),
    );
    final sb = GameSession(
      r[1],
      b.messenger,
      p2p: pb,
      helloInterval: const Duration(milliseconds: 50),
    );
    await sa.start();
    await pump(200); // the second player joins later
    await sb.start();
    await pump(200);
    return (sa, sb);
  }

  test('session over relays delivers messages in order', () async {
    final bus = FakeRelayBus();
    final (sa, sb) = await connect(bus);
    expect(sa.state, LinkState.connected);
    expect(sb.state, LinkState.connected);
    expect(sa.isDirect, isFalse);
    final got = <int>[];
    sb.messages.listen((m) => got.add(m['n'] as int));
    for (var i = 0; i < 20; i++) {
      sa.send({'n': i});
    }
    await pump(200);
    expect(got, List.generate(20, (i) => i));
  });

  test('session switches to direct p2p and keeps order across paths', () async {
    final bus = FakeRelayBus();
    final (sa, sb) = await connect(bus, withP2p: true);
    expect(sa.isDirect, isTrue);
    expect(sb.isDirect, isTrue);
    final relayedBefore = bus.published.length;
    final got = <String>[];
    sa.messages.listen((m) => got.add(m['v'] as String));
    sb.send({'v': 'a'});
    sb.send({'v': 'b'});
    await pump(100);
    expect(got, ['a', 'b']);
    expect(
      bus.published.length,
      relayedBefore,
      reason: 'direct path does not use relays',
    );
  });

  test('relay keepalive: idle but alive players stay connected', () async {
    final bus = FakeRelayBus();
    final a = Player(bus, 'A'), b = Player(bus, 'B');
    final r = await Future.wait([
      a.matchmaker.findRandom('x'),
      b.matchmaker.findRandom('x'),
    ]);
    GameSession make(MatchInfo m, Messenger msg) => GameSession(
      m,
      msg,
      helloInterval: const Duration(milliseconds: 20),
      pingInterval: const Duration(milliseconds: 30),
      timeout: const Duration(milliseconds: 150),
    );
    final sa = make(r[0], a.messenger), sb = make(r[1], b.messenger);
    await sa.start();
    await sb.start();
    await pump(600); // four times the timeout without any game message
    expect(sa.state, LinkState.connected);
    expect(sb.state, LinkState.connected);
    await sb.close();
    await pump(400);
    expect(sa.state, LinkState.opponentLeft);
  });

  test('leaving notifies the opponent', () async {
    final bus = FakeRelayBus();
    final (sa, sb) = await connect(bus);
    final states = <LinkState>[];
    sb.stateChanges.listen(states.add);
    await sa.close();
    await pump(100);
    expect(states, contains(LinkState.opponentLeft));
  });
}
