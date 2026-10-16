import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/account.dart';
import 'package:mobile_games/core/leaderboard.dart';
import 'package:mobile_games/core/nostr/event.dart';
import 'package:mobile_games/games/yahtzee/kniffel_proof.dart';
import 'package:mobile_games/games/yahtzee/yahtzee_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';

/// Plays a whole solo game with the computer's strategy, recording it.
(KniffelProof, int) playProven(String pubkey) {
  final proof = KniffelProof.start(pubkey);
  final g = proof.newGame();
  final ai = KniffelAi();
  while (!g.isOver) {
    proof.roll(g);
    g.roll();
    final sheet = g.sheets[0];
    if (g.canRoll) {
      final holds = ai.chooseHolds(g.dice, sheet, g.rollsLeft);
      if (!holds.every((h) => h)) {
        g.held = holds;
        continue;
      }
    }
    final (cat, _) = ai.bestCategory(g.dice, sheet);
    proof.score(cat);
    g.score(cat);
  }
  return (proof, g.sheets[0].total);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Leaderboard.instance = null;
  });

  test('seeded dice are the same everywhere and fair', () {
    final a = SeededDice('x'), b = SeededDice('x');
    final rolls = [for (var i = 0; i < 6000; i++) a.nextInt(6)];
    expect([for (var i = 0; i < 6000; i++) b.nextInt(6)], rolls);
    for (var v = 0; v < 6; v++) {
      final n = rolls.where((r) => r == v).length;
      expect(n, inInclusiveRange(850, 1150));
    }
  });

  test('a played game proves its score, changes are caught', () {
    final (proof, total) = playProven('anna');
    expect(proof.verify('anna'), total);
    // Somebody else's game does not count as mine.
    expect(proof.verify('ben'), isNull);
    // Changed moves: another category, or a game not played to the end.
    final moves = List.of(proof.moves);
    final i = moves.lastIndexWhere((m) => !m.startsWith('r'));
    final other = KniffelCategory.values.firstWhere(
      (c) => c.name != moves[i] && !moves.contains(c.name),
      orElse: () => KniffelCategory.chance,
    );
    expect(
      KniffelProof(proof.seed, List.of(moves)..[i] = other.name).verify('anna'),
      isNot(total),
    );
    expect(
      KniffelProof(
        proof.seed,
        moves.sublist(0, moves.length - 1),
      ).verify('anna'),
      isNull,
    );
    // Rolling four times in a turn is impossible.
    expect(KniffelProof(proof.seed, ['r0', 'r0', 'r0', 'r0']).replay(), isNull);
    // Survives the trip through JSON.
    final back = KniffelProof.fromJson(jsonDecode(jsonEncode(proof.toJson())))!;
    expect(back.verify('anna'), total);
  });

  test('typed-in scores do not reach the world ranking', () async {
    final bus = FakeRelayBus();
    final a = await Account.load(prefix: 'a');
    await a.setName('Anna');
    final lb = Leaderboard(bus.client(), a);

    // A real game is published with its record.
    final (proof, total) = playProven(a.keys.publicKey);
    await Leaderboard.submit('kniffel', total, proof: proof.toJson());
    await lb.publish();
    var all = await lb.fetch(timeout: const Duration(milliseconds: 50));
    expect(all.single.scores['kniffel'], total);

    // Console: a better value without a game behind it.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lb.kniffel',
      jsonEncode([
        {'v': 375, 't': 0},
      ]),
    );
    await Leaderboard.submit('labyrinth', 5);
    await lb.publish();
    final sent = jsonDecode(bus.published.last.content) as Map;
    expect(
      (sent['s'] as Map)['kniffel'],
      isNull,
      reason: 'a value without its game is not published',
    );

    // Publishing a made-up event directly (with someone else's real game).
    final c = await Account.load(prefix: 'c');
    await bus.client().publish(
      NostrEvent.create(
        keys: c.keys,
        kind: Leaderboard.kind,
        content: jsonEncode({
          'name': 'Mogel',
          's': {'kniffel': total},
          'p': {'kniffel': proof.toJson()},
        }),
        tags: [
          ['d', 'mobilegames-scores'],
          ['t', 'mobilegames-scores'],
        ],
      ),
    );
    all = await lb.fetch(timeout: const Duration(milliseconds: 50));
    final mogel = all.firstWhere((r) => r.name == 'Mogel');
    expect(mogel.scores['kniffel'], isNull);
  });

  test(
    'values from before the check keep counting, but no better ones',
    () async {
      final bus = FakeRelayBus();
      final a = await Account.load(prefix: 'a');
      await a.setName('Anna');
      final lb = Leaderboard(bus.client(), a);
      Leaderboard.legacy = {
        a.keys.publicKey: {'kniffel': 300, 'snake': 40},
      };
      addTearDown(() => Leaderboard.legacy = {});

      // The old values on the device are published without a game.
      await Leaderboard.submit('kniffel', 300);
      await Leaderboard.submit('snake', 35);
      await lb.publish();
      var all = await lb.fetch(timeout: const Duration(milliseconds: 50));
      expect(all.single.scores['kniffel'], 300);
      expect(
        all.single.scores['snake'],
        35,
        reason: 'worse than before is fine',
      );

      // Better than before without a game: not published, not shown.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'lb.kniffel',
        jsonEncode([
          {'v': 375, 't': 0},
          {'v': 300, 't': 0},
        ]),
      );
      await lb.publish();
      final sent = jsonDecode(bus.published.last.content) as Map;
      expect((sent['s'] as Map)['kniffel'], 300, reason: 'the old value stays');

      // A made-up event with more than the old value is ignored.
      await bus.client().publish(
        NostrEvent.create(
          keys: a.keys,
          kind: Leaderboard.kind,
          content: jsonEncode({
            'name': 'Anna',
            's': {'kniffel': 375},
          }),
          createdAt: DateTime.now().add(const Duration(seconds: 5)),
          tags: [
            ['d', 'mobilegames-scores'],
            ['t', 'mobilegames-scores'],
          ],
        ),
      );
      all = await lb.fetch(timeout: const Duration(milliseconds: 50));
      expect(all.single.scores['kniffel'], isNull);
    },
  );
}
