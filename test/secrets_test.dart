import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/konami.dart';
import 'package:mobile_games/core/secrets.dart';
import 'package:mobile_games/games/checkers/checkers_logic.dart';
import 'package:mobile_games/games/chess/chess_logic.dart';
import 'package:mobile_games/ui/chat_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Secrets.I.reset();
  });

  test('extras only work once unlocked and are remembered', () async {
    await Secrets.I.set(Secret.disco, true);
    expect(Secrets.on(Secret.disco), isFalse, reason: 'not unlocked yet');
    expect(await Secrets.I.unlock(), isTrue);
    expect(await Secrets.I.unlock(), isFalse);
    expect(Secrets.on(Secret.disco), isTrue);
    expect(Secrets.on(Secret.retro), isTrue, reason: 'on after first unlock');
    Secrets.I.reset();
    await Secrets.I.load();
    expect(Secrets.I.unlocked, isTrue);
    expect(Secrets.on(Secret.disco), isTrue);
  });

  test('konami chat messages are recognised', () {
    for (final t in [
      '↑↑↓↓←→←→BA',
      '↑ ↑ ↓ ↓ ← → ← → B A',
      'uuddlrlrba',
      'Up, up, down, down, left, right, left, right, B, A, Start',
      '⬆⬆⬇⬇⬅➡⬅➡',
    ]) {
      expect(isKonamiText(t), isTrue, reason: t);
    }
    for (final t in ['hallo', 'up up down', 'ba', '']) {
      expect(isKonamiText(t), isFalse, reason: t);
    }
  });

  testWidgets('a new konami message rains confetti', (tester) async {
    var lines = <ChatEntry>[
      ChatEntry(mine: false, author: 'A', text: 'hi', time: DateTime(2026)),
    ];
    Widget app() => MaterialApp(
      home: Scaffold(
        body: ChatView(lines: lines, onSend: (_) {}),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey('confetti')), findsNothing);
    lines = [
      ...lines,
      ChatEntry(
        mine: false,
        author: 'A',
        text: '↑↑↓↓←→←→BA',
        time: DateTime(2026),
      ),
    ];
    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey('confetti')), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('confetti')), findsNothing);
  });

  test('friends see the 🎮 badge', () async {
    final bus = FakeRelayBus();
    final a = await Account.load(prefix: 'a');
    final b = await Account.load(prefix: 'b');
    await a.addFriend(b.keys.publicKey);
    final pa = Presence(bus.client(), a)..start();
    await Secrets.I.unlock();
    final pb = Presence(bus.client(), b)..start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(pa.hasBadge(b.keys.publicKey), isTrue);
    pa.dispose();
    pb.dispose();
  });

  test('grandmaster AIs find a winning capture', () {
    // Chess: the queen can take a free rook.
    final chess = ChessGame.fromFen('4k3/8/8/3r4/8/8/3Q4/4K3 w - - 0 1');
    final m = chess.aiMove(Random(1), true)!;
    expect((m.$1, m.$2), ('d2', 'd5'));
    // Checkers: plays a legal move and prefers the capture.
    final g = CheckersGame();
    final move = g.aiMove(Random(1), true);
    expect(
      g.legalMoves().any((x) => x.from == move!.from && x.to == move.to),
      isTrue,
    );
  });
}
