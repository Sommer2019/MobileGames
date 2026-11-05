import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_games/games/geobingo/geobingo_logic.dart';
import 'package:mobile_games/games/geobingo/regions.dart';

Map<String, dynamic> view(String id, {String cc = 'de'}) => GeoView(
  source: GeoSource.google,
  id: id,
  lat: 52.5,
  lng: 13.4,
  heading: 90,
  country: cc,
).toJson();

GeoBingoGame hunting({int players = 3, List<String> blocked = const []}) {
  final g = GeoBingoGame(players: players);
  expect(
    g.apply([
      'cfg',
      {'min': 5, 'src': 'google', 'blocked': blocked},
    ], 0),
    isTrue,
  );
  g.apply(['term', 'Feuerwehrauto'], 0);
  g.apply(['term', 'Kirche'], 0);
  expect(g.apply(['start', 1000], 0), isTrue);
  return g;
}

void main() {
  test('only the host sets up; others suggest terms', () {
    final g = GeoBingoGame(players: 2);
    expect(g.apply(['term', 'Ampel'], 1), isFalse);
    expect(
      g.apply([
        'cfg',
        {'min': 5, 'src': 'google', 'blocked': <String>[]},
      ], 1),
      isFalse,
    );
    expect(g.apply(['prop', '  Rotes   Auto '], 1), isTrue);
    expect(g.proposals.single, (1, 'Rotes Auto'));
    expect(g.apply(['prop', 'rotes auto'], 1), isFalse, reason: 'twice');
    expect(g.apply(['acc', 'Rotes Auto'], 1), isFalse);
    expect(g.apply(['acc', 'Rotes Auto'], 0), isTrue);
    expect(g.terms, ['Rotes Auto']);
    expect(g.apply(['prop', 'Rotes Auto'], 1), isFalse, reason: 'is a term');
    g.apply(['prop', 'Katze'], 1);
    expect(g.apply(['rej', 'Katze'], 0), isTrue);
    expect(g.proposals, isEmpty);
    expect(g.terms, ['Rotes Auto']);
    expect(g.apply(['start', 5], 1), isFalse);
  });

  test('no start without terms, bad settings are refused', () {
    final g = GeoBingoGame(players: 2);
    expect(g.apply(['start', 1], 0), isFalse);
    expect(
      g.apply([
        'cfg',
        {'min': 0, 'src': 'google', 'blocked': <String>[]},
      ], 0),
      isFalse,
    );
    expect(
      g.apply([
        'cfg',
        {'min': 3, 'src': 'bing', 'blocked': <String>[]},
      ], 0),
      isFalse,
    );
    expect(g.apply(['term', 'x' * 41], 0), isFalse);
  });

  test('finds: one per term, blocked regions and wrong sources refused', () {
    final g = hunting(blocked: ['fr', 'c:AS']);
    expect(g.phase, GeoPhase.hunt);
    expect(g.timeLeft(1000 + 60000), 4 * 60000);
    expect(g.timeLeft(1000 + 6 * 60000), 0);
    expect(g.apply(['find', 0, view('a')], 1), isTrue);
    expect(g.apply(['find', 0, view('b')], 1), isTrue, reason: 'replaces');
    expect(g.finds[1]![0]!.id, 'b');
    expect(g.apply(['find', 1, view('c', cc: 'fr')], 1), isFalse);
    expect(g.apply(['find', 1, view('c', cc: 'jp')], 1), isFalse);
    expect(g.apply(['find', 2, view('c')], 1), isFalse, reason: 'no term 2');
    final mapillary = {...view('m'), 'src': 'mapillary'};
    expect(g.apply(['find', 1, mapillary], 1), isFalse);
    expect(g.apply(['find', 1, view('d', cc: '')], 2), isTrue);
  });

  test('the host review decides the finds, ratings give the points', () {
    final g = hunting();
    g.apply(['find', 0, view('late')], 2); // the host never got this one
    final hostFinds = {
      '0': {'0': view('a0'), '1': view('a1')},
      '1': {'0': view('b0')},
    };
    expect(g.apply(['review', hostFinds], 0), isTrue);
    expect(g.finds[2], isNull);
    expect(g.apply(['find', 1, view('x')], 1), isFalse, reason: 'too late');
    expect(g.toRate(2), [(0, 0), (1, 0), (0, 1)]);
    expect(g.toRate(0), [(1, 0)]);
    expect(g.apply(['rate', 0, 0, 5], 0), isFalse, reason: 'own find');
    expect(g.apply(['rate', 2, 0, 5], 0), isFalse, reason: 'no find');
    expect(g.apply(['rate', 1, 0, 6], 0), isFalse);
    g.apply(['rate', 1, 0, 2], 0);
    g.apply(['rate', 1, 0, 4], 2);
    g.apply(['rate', 0, 0, 5], 1);
    g.apply(['rate', 0, 0, 5], 2);
    expect(g.average(1, 0), 3);
    expect(g.findPoints(1, 0), 60);
    expect(g.findPoints(0, 0), 100);
    expect(g.findPoints(0, 1), 60, reason: 'unrated: 3 stars');
    expect(g.findPoints(2, 0), 0);
    expect(g.currentScores(), [160, 60, 0]);
    expect(g.allRated, isFalse);
    g.apply(['rated'], 0);
    g.apply(['rated'], 1);
    expect(g.allRated, isFalse);
    g.apply(['rated'], 2);
    expect(g.allRated, isTrue);
    expect(g.apply(['end', g.currentScores()], 1), isFalse);
    expect(g.apply(['end', g.currentScores()], 0), isTrue);
    expect(g.isOver, isTrue);
    expect(g.winners(), [0]);
    // Next round: same terms, everything else fresh.
    expect(g.apply(['new'], 0), isTrue);
    expect(g.phase, GeoPhase.setup);
    expect(g.terms, ['Feuerwehrauto', 'Kirche']);
    expect(g.finds, isEmpty);
    expect(g.ratings, isEmpty);
  });

  test('replaying the events gives the same game', () {
    final g = hunting();
    g.apply(['find', 0, view('a')], 1);
    g.apply([
      'review',
      {
        '1': {'0': view('a')},
      },
    ], 0);
    g.apply(['rate', 1, 0, 4], 0);
    final r = GeoBingoGame.replay(3, g.events);
    expect(r.phase, GeoPhase.review);
    expect(r.average(1, 0), 4);
    expect(r.terms, g.terms);
  });

  test('views survive the trip as JSON, broken ones are refused', () {
    final v = GeoView.fromJson(view('p', cc: 'DE'))!;
    expect(v.id, 'p');
    expect(v.heading, 90);
    expect(v.country, 'de');
    expect(
      GeoView.fromJson({'src': 'google', 'id': 'x', 'lat': 91, 'lng': 0}),
      isNull,
    );
    expect(
      GeoView.fromJson({'src': 'google', 'id': '', 'lat': 1, 'lng': 0}),
      isNull,
    );
    expect(GeoView.fromJson('nope'), isNull);
  });

  test('regions: countries and whole continents', () {
    expect(isBlocked('fr', ['c:EU']), isTrue);
    expect(isBlocked('jp', ['c:EU']), isFalse);
    expect(isBlocked('jp', ['jp']), isTrue);
    expect(isBlocked('', ['c:EU']), isFalse);
    expect(countryByCode['de']!.name, 'Deutschland');
    expect(blockedLabel(['c:AS', 'fr']), 'Asien, Frankreich');
    expect(blockedLabel([]), 'keine');
    expect(countries.map((c) => c.code).toSet(), hasLength(countries.length));
    for (final c in countries) {
      expect(continents, contains(c.continent), reason: c.name);
    }
  });
}
