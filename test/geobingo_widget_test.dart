import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/geobingo/geobingo_logic.dart';
import 'package:mobile_games/games/geobingo/geobingo_screen.dart';
import 'package:mobile_games/games/geo/street_view.dart';
import 'package:mobile_games/ui/play_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_nostr.dart';
import 'room_util.dart';

/// Marks a fixed spot instead of asking a real panorama.
class FakeMarker extends StreetViewController {
  FakeMarker(this.id);
  final String id;

  @override
  Future<(GeoView?, String?)> mark() async => (
    GeoView(
      source: GeoSource.google,
      id: id,
      lat: 48.1,
      lng: 11.6,
      country: 'de',
    ),
    null,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Panoramax works without a key, the others need one', () {
    expect(GeoSource.panoramax.needsKey, isFalse);
    expect(availableSources, contains(GeoSource.panoramax));
    expect(availableSources, isNot(contains(GeoSource.google)));
  });

  testWidgets('Geobingo: suggest, start, mark, rate, winner', (tester) async {
    tester.view.physicalSize = const Size(2200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rooms = (await tester.runAsync(
      () => buildRoom(
        FakeRelayBus(),
        1,
        gameId: 'geobingo',
        names: ['Anna', 'Ben'],
      ),
    ))!;
    Widget screen(int seat) => GeoBingoScreen(
      setup: PlaySetup.online(rooms[seat]),
      sources: const [GeoSource.google],
      huntController: FakeMarker('spot$seat'),
      viewBuilder: (mode) => ColoredBox(
        key: ValueKey('fakeView-${mode.name}'),
        color: Colors.grey,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(
              child: KeyedSubtree(key: const ValueKey('A'), child: screen(0)),
            ),
            Expanded(
              child: KeyedSubtree(key: const ValueKey('B'), child: screen(1)),
            ),
          ],
        ),
      ),
    );
    Finder on(String side, Finder f) =>
        find.descendant(of: find.byKey(ValueKey(side)), matching: f);
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
    }

    await settle();
    // Anna adds a term, Ben suggests one, Anna accepts it.
    await tester.enterText(
      on('A', find.byKey(const ValueKey('gbTermField'))),
      'Feuerwehrauto',
    );
    await tester.tap(on('A', find.byKey(const ValueKey('gbAddTerm'))));
    await tester.enterText(
      on('B', find.byKey(const ValueKey('gbTermField'))),
      'Kirche',
    );
    await tester.tap(on('B', find.byKey(const ValueKey('gbAddTerm'))));
    await settle();
    expect(on('B', find.text('Feuerwehrauto')), findsOneWidget);
    await tester.tap(on('A', find.byKey(const ValueKey('gbAcc-Kirche'))));
    await settle();
    expect(on('B', find.byKey(const ValueKey('gbTerm1'))), findsOneWidget);
    expect(on('B', find.byKey(const ValueKey('gbStart'))), findsNothing);
    await tester.tap(on('A', find.byKey(const ValueKey('gbStart'))));
    await settle();
    // Both hunt; each marks the first term.
    expect(
      on('B', find.byKey(const ValueKey('fakeView-hunt'))),
      findsOneWidget,
    );
    await tester.tap(on('A', find.byKey(const ValueKey('gbMark'))));
    await tester.tap(on('B', find.byKey(const ValueKey('gbMark'))));
    await settle();
    expect(on('A', find.textContaining('gefunden 1/2')), findsOneWidget);
    await tester.tap(on('A', find.byKey(const ValueKey('gbEndHunt'))));
    await settle();
    // Rating: Anna gives Ben 5 stars, Ben gives Anna 2.
    expect(on('A', find.textContaining('von Ben')), findsOneWidget);
    await tester.tap(on('A', find.byKey(const ValueKey('gbStar5'))));
    await tester.tap(on('B', find.byKey(const ValueKey('gbStar2'))));
    await tester.pump();
    await tester.tap(on('A', find.byKey(const ValueKey('gbRated'))));
    await tester.tap(on('B', find.byKey(const ValueKey('gbRated'))));
    await settle();
    expect(on('A', find.textContaining('Ben gewinnt')), findsOneWidget);
    expect(on('B', find.textContaining('Du gewinnst')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });
}
