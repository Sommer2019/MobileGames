import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/core/mirror.dart';
import 'package:mobile_games/core/saved_games.dart';
import 'package:mobile_games/games/labyrinth/labyrinth_screen.dart';
import 'package:mobile_games/games/registry.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:mobile_games/ui/watch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Games played on one device and how they are started for the test.
final cases = <(String, PlaySetup?)>[
  ('boxes', const PlaySetup.local(players: 2, bots: {0, 1})),
  ('ludo', const PlaySetup.local(players: 3, bots: {0, 1, 2})),
  ('domino', const PlaySetup.local(players: 2, bots: {0, 1})),
  ('halma', const PlaySetup.local(players: 2, bots: {0, 1})),
  ('lastcard', const PlaySetup.local(players: 3, bots: {0, 1, 2})),
  ('stapelfix', const PlaySetup.local(players: 2, bots: {0, 1})),
  ('billiard', const PlaySetup.local(players: 2, bots: {0, 1})),
  ('chess', const PlaySetup.ai()),
  ('checkers', const PlaySetup.ai()),
  ('mill', const PlaySetup.ai()),
  ('connect_four', const PlaySetup.ai()),
  ('yahtzee', const PlaySetup.ai()),
  ('battleship', const PlaySetup.ai()),
  ('battleship', const PlaySetup.local()),
  ('mahjong', null),
  ('klondike', null),
  ('snake', null),
  ('arrows', null),
  ('dice', null),
  ('billiard', const PlaySetup.local(players: 1)),
  ('darts', const PlaySetup.local(players: 1)),
  ('darts', const PlaySetup.local(players: 2)),
  ('bingo', const PlaySetup.local(players: 3, bots: {1, 2})),
  ('labyrinth', null),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedGames.reset();
    Mirrors.current.value = null;
  });

  for (final (id, setup) in cases) {
    testWidgets('$id ${setup?.kind.name ?? 'allein'} ${setup?.players ?? ''}: '
        'a friend sees the game', (tester) async {
      tester.view.physicalSize = const Size(2400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final game = gameById(id)!;
      final source = id == 'labyrinth'
          ? const LabyrinthScreen(levelIndex: 2)
          : setup == null
          ? game.singleplayerBuilder!()
          : game.multiplayerBuilder!(setup);
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              Expanded(child: source),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      await tester.pump();
      final mirror = Mirrors.current.value;
      expect(mirror, isNotNull, reason: 'the game offers itself');
      expect(mirror!.mirrorGame, id);
      final feed = MirrorFeed(
        gameId: id,
        friendName: 'Anna',
        setup: mirror.mirrorSetup,
        state: mirror.mirrorState(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              Expanded(child: source),
              Expanded(child: MirrorWatchScreen(feed: feed)),
            ],
          ),
        ),
      );
      // The game goes on; the state is sent over now and then.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        final s = mirror.mirrorState();
        if (s != null) feed.state.value = s;
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('👁 Du schaust Anna zu'), findsOneWidget);
      // The watching screen shows exactly the same game.
      final watching = tester.allStates.whereType<GameMirror>().firstWhere(
        (s) => s.mirroring,
      );
      final sent = mirror.mirrorState();
      if (sent != null) {
        feed.state.value = sent;
        await tester.pump();
        expect(
          jsonEncode(watching.mirrorState()),
          jsonEncode(sent),
          reason: 'mirror of $id',
        );
      }
      // Watching saves nothing and does not take over.
      expect(Mirrors.current.value, same(mirror));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
