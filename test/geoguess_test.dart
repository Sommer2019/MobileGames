import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/geo/street_view.dart';
import 'package:mobile_games/games/geoguess/geoguess_logic.dart';
import 'package:mobile_games/games/geoguess/geoguess_screen.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> berlin() => const GeoView(
  source: GeoSource.panoramax,
  id: 'b',
  lat: 52.52,
  lng: 13.405,
  country: 'de',
).toJson();

/// Answers like the street picture page, without a page.
class FakePage extends StreetViewController {
  @override
  Future<(GeoView?, String?)> random(List<GeoSource> sources) async =>
      (GeoView.fromJson(berlin()), null);

  @override
  Future<((double, double)?, String?)> guess() async =>
      ((48.137, 11.575), null); // Munich, ~504 km away
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('distances and points', () {
    expect(distanceKm(52.52, 13.405, 48.137, 11.575), closeTo(504, 3));
    expect(pointsFor(0), 5000);
    expect(pointsFor(1400), closeTo(2483, 5));
    expect(pointsFor(20000), lessThan(1));
    expect(formatDistance(0.34), '340 m');
    expect(formatDistance(1.25), '1,3 km');
    expect(formatDistance(12345), '12.345 km');
  });

  test('rounds, guesses, the host reveal decides', () {
    final g = GeoGuessGame(players: 2);
    expect(
      g.apply([
        'cfg',
        {
          'rounds': 2,
          'sec': 60,
          'src': ['panoramax'],
        },
      ], 0),
      isTrue,
    );
    expect(
      g.apply([
        'cfg',
        {
          'rounds': 2,
          'sec': 7,
          'src': ['panoramax'],
        },
      ], 0),
      isFalse,
    );
    expect(g.apply(['round', 0, berlin(), 1000], 1), isFalse);
    final google = {...berlin(), 'src': 'google'};
    expect(g.apply(['round', 0, google, 1000], 0), isFalse, reason: 'source');
    expect(g.apply(['round', 0, berlin(), 1000], 0), isTrue);
    expect(g.timeLeft(31000), 30000);
    expect(g.apply(['guess', 0, 48.137, 11.575], 1), isTrue);
    expect(g.apply(['guess', 0, 0, 0], 1), isFalse, reason: 'once');
    expect(g.apply(['guess', 0, 52.52, 13.405], 0), isTrue);
    expect(g.allGuessed, isTrue);
    expect(
      g.apply([
        'reveal',
        0,
        {
          '0': [52.52, 13.405],
          '1': [48.137, 11.575],
        },
      ], 0),
      isTrue,
    );
    expect(g.roundPoints(0, 0), 5000);
    expect(g.roundPoints(0, 1), closeTo(3888, 10));
    expect(g.apply(['end'], 0), isFalse, reason: 'one round left');
    g.apply(['round', 1, berlin(), 2000], 0);
    g.apply([
      'reveal',
      1,
      {
        '1': [52.52, 13.405],
      },
    ], 0);
    expect(g.roundPoints(1, 0), 0, reason: 'no guess');
    expect(g.apply(['end'], 0), isTrue);
    expect(g.total(0), 5000);
    expect(g.total(1), closeTo(8888, 10));
    expect(g.winners(), [1]);
    expect(GeoGuessGame.replay(2, g.events).total(1), g.total(1));
  });

  testWidgets('Wo bin ich? alone: guess, reveal, result', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GeoGuessScreen(
          setup: const PlaySetup.local(players: 1),
          sources: const [GeoSource.panoramax],
          controller: FakePage(),
          viewBuilder: () => const ColoredBox(color: Colors.grey),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('ggRounds')),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(find.text('Runden: 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ggStart')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Runde 1/1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ggGuess')));
    await tester.pumpAndSettle();
    expect(find.text('504 km'), findsOneWidget);
    expect(find.text('📍 Deutschland'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ggNext')));
    await tester.pumpAndSettle();
    expect(find.textContaining('von 5000 Punkten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
