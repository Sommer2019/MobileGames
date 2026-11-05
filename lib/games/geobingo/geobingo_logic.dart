import 'dart:math';

import 'regions.dart';

/// Where the street pictures come from.
enum GeoSource {
  google('Google Street View'),
  mapillary('Mapillary');

  const GeoSource(this.label);
  final String label;
}

/// A marked spot in a street panorama: the picture and the direction the
/// player looked in when marking it.
class GeoView {
  const GeoView({
    required this.source,
    required this.id,
    required this.lat,
    required this.lng,
    this.heading = 0,
    this.pitch = 0,
    this.zoom = 1,
    this.country = '',
  });

  final GeoSource source;

  /// Google panorama id or Mapillary image id.
  final String id;
  final double lat;
  final double lng;
  final double heading;
  final double pitch;
  final double zoom;

  /// ISO country code (lower case), '' if unknown.
  final String country;

  static GeoView? fromJson(Object? j) {
    if (j is! Map) return null;
    final src = GeoSource.values.asNameMap()[j['src']];
    final id = j['id'];
    num? n(String k) => j[k] is num ? j[k] as num : null;
    final lat = n('lat'), lng = n('lng');
    if (src == null || id is! String || id.isEmpty || id.length > 200) {
      return null;
    }
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    final cc = j['cc'];
    return GeoView(
      source: src,
      id: id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      heading: (n('h') ?? 0).toDouble(),
      pitch: (n('p') ?? 0).toDouble(),
      zoom: (n('z') ?? 1).toDouble(),
      country: cc is String && cc.length <= 3 ? cc.toLowerCase() : '',
    );
  }

  Map<String, dynamic> toJson() => {
    'src': source.name,
    'id': id,
    'lat': lat,
    'lng': lng,
    'h': heading,
    'p': pitch,
    'z': zoom,
    if (country.isNotEmpty) 'cc': country,
  };
}

enum GeoPhase { setup, hunt, review, results }

/// Geobingo: everybody looks for the same terms anywhere in the world's
/// street pictures, marks one view per term, and afterwards rates the
/// finds of the others.
///
/// The host decides: terms, time, blocked regions and the picture source.
/// The others may suggest terms, which the host accepts or turns down.
/// After the time is up everybody rates every find of the others with 1–5
/// stars; a find scores its average × 20 (at most 100 per term).
///
/// Played through [apply] with plain events (seat of the sender given):
/// host only: `['cfg', {min, src, blocked}]`, `['term', text]`,
/// `['del', i]`, `['acc', text]`, `['rej', text]`, `['start', epochMs]`,
/// `['review', finds]`, `['end', scores]`, `['new']` (next round with the same
/// terms); everybody: `['prop', text]`,
/// `['find', termIndex, view]`,
/// `['rate', owner, termIndex, stars]`, `['rated']`.
/// The host's `review` and `end` carry the finds and scores as the host
/// has them, so every device shows the same result even when a late
/// message only reached some of them.
class GeoBingoGame {
  GeoBingoGame({required this.players, GeoSource? source})
    : source = source ?? GeoSource.google;

  static const maxTerms = 25;
  static const maxTermLength = 40;
  static const minMinutes = 1;
  static const maxMinutes = 60;

  final int players;
  final List<List> events = [];

  GeoPhase phase = GeoPhase.setup;
  int minutes = 10;
  GeoSource source;
  List<String> blocked = [];
  final List<String> terms = [];

  /// Suggested terms with who suggested them.
  final List<(int, String)> proposals = [];

  /// Host clock when the hunt started.
  int startedAt = 0;

  /// seat → term index → marked view.
  final Map<int, Map<int, GeoView>> finds = {};

  /// rater → "owner:term" → stars.
  final Map<int, Map<String, int>> ratings = {};
  final Set<int> doneRating = {};

  /// Final points per seat (from the host).
  List<double> scores = [];

  bool get isOver => phase == GeoPhase.results;

  int get durationMs => minutes * 60000;

  static String clean(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static bool validTerm(String t) => t.isNotEmpty && t.length <= maxTermLength;

  bool _hasTerm(String t) =>
      terms.any((x) => x.toLowerCase() == t.toLowerCase());

  bool apply(List e, int seat) {
    final host = seat == 0;
    switch (e) {
      case ['cfg', final Map c] when host && phase == GeoPhase.setup:
        final min = c['min'], src = c['src'], bl = c['blocked'];
        if (min is! int || min < minMinutes || min > maxMinutes) return false;
        final s = GeoSource.values.asNameMap()[src];
        if (s == null || bl is! List || bl.length > 300) return false;
        if (bl.any((b) => b is! String || b.length > 4)) return false;
        minutes = min;
        source = s;
        blocked = bl.cast<String>().toList();
      case ['term', final String raw] when host && phase == GeoPhase.setup:
        final t = clean(raw);
        if (!validTerm(t) || _hasTerm(t) || terms.length >= maxTerms) {
          return false;
        }
        terms.add(t);
        proposals.removeWhere((p) => p.$2.toLowerCase() == t.toLowerCase());
      case ['del', final int i] when host && phase == GeoPhase.setup:
        if (i < 0 || i >= terms.length) return false;
        terms.removeAt(i);
      case ['prop', final String raw] when phase == GeoPhase.setup:
        final t = clean(raw);
        if (!validTerm(t) || _hasTerm(t)) return false;
        if (proposals.any((p) => p.$2.toLowerCase() == t.toLowerCase())) {
          return false;
        }
        if (proposals.where((p) => p.$1 == seat).length >= 10) return false;
        proposals.add((seat, t));
      case ['acc', final String t] when host && phase == GeoPhase.setup:
        final i = proposals.indexWhere((p) => p.$2 == t);
        if (i < 0 || terms.length >= maxTerms) return false;
        proposals.removeAt(i);
        if (!_hasTerm(t)) terms.add(t);
      case ['rej', final String t] when host && phase == GeoPhase.setup:
        final i = proposals.indexWhere((p) => p.$2 == t);
        if (i < 0) return false;
        proposals.removeAt(i);
      case ['start', final int at] when host && phase == GeoPhase.setup:
        if (terms.isEmpty) return false;
        startedAt = at;
        proposals.clear();
        phase = GeoPhase.hunt;
      case ['find', final int i, final Object? v] when phase == GeoPhase.hunt:
        final view = GeoView.fromJson(v);
        if (view == null || i < 0 || i >= terms.length || seat >= players) {
          return false;
        }
        if (view.source != source || isBlocked(view.country, blocked)) {
          return false;
        }
        (finds[seat] ??= {})[i] = view;
      case ['review', final Map f] when host && phase == GeoPhase.hunt:
        finds.clear();
        for (final MapEntry(:key, :value) in f.entries) {
          final s = int.tryParse('$key');
          if (s == null || s < 0 || s >= players || value is! Map) continue;
          for (final MapEntry(key: k, value: v) in value.entries) {
            final i = int.tryParse('$k');
            final view = GeoView.fromJson(v);
            if (i == null || i < 0 || i >= terms.length || view == null) {
              continue;
            }
            (finds[s] ??= {})[i] = view;
          }
        }
        phase = GeoPhase.review;
      case ['rate', final int owner, final int i, final int stars]
          when phase == GeoPhase.review:
        if (owner == seat || stars < 1 || stars > 5) return false;
        if (finds[owner]?[i] == null) return false;
        (ratings[seat] ??= {})['$owner:$i'] = stars;
      case ['rated'] when phase == GeoPhase.review:
        doneRating.add(seat);
      case ['end', final List s] when host && phase == GeoPhase.review:
        if (s.length != players || s.any((x) => x is! num)) return false;
        scores = [for (final x in s) (x as num).toDouble()];
        phase = GeoPhase.results;
      case ['new'] when host && phase == GeoPhase.results:
        phase = GeoPhase.setup;
        finds.clear();
        ratings.clear();
        doneRating.clear();
        scores = [];
        proposals.clear();
      default:
        return false;
    }
    events.add([seat, ...e]);
    return true;
  }

  /// Replays [log] (entries `[seat, ...event]`, see [events]).
  factory GeoBingoGame.replay(int players, List log) {
    final g = GeoBingoGame(players: players);
    for (final x in log) {
      final l = List.from(x as List);
      g.apply(l.sublist(1), l.first as int);
    }
    return g;
  }

  /// Time left of the hunt in milliseconds (against [now], host clock).
  int timeLeft(int now) => max(0, startedAt + durationMs - now);

  /// The finds to rate by [rater]: (owner, term index).
  List<(int, int)> toRate(int rater) => [
    for (var i = 0; i < terms.length; i++)
      for (var p = 0; p < players; p++)
        if (p != rater && finds[p]?[i] != null) (p, i),
  ];

  int? ratingBy(int rater, int owner, int term) =>
      ratings[rater]?['$owner:$term'];

  /// Average stars of a find, null if nobody rated it.
  double? average(int owner, int term) {
    final stars = [for (final r in ratings.values) ?r['$owner:$term']];
    if (stars.isEmpty) return null;
    return stars.reduce((a, b) => a + b) / stars.length;
  }

  /// Points of a find: average stars × 20; a find nobody rated counts 3
  /// stars (it was found, nobody objected).
  double findPoints(int owner, int term) {
    if (finds[owner]?[term] == null) return 0;
    return (average(owner, term) ?? 3) * 20;
  }

  /// Points per seat as they are now (the host sends these with `end`).
  List<double> currentScores() => [
    for (var p = 0; p < players; p++)
      [for (var i = 0; i < terms.length; i++) findPoints(p, i)]
          .fold(0.0, (a, b) => a + b),
  ];

  /// Everybody (who has something to rate) is done.
  bool get allRated =>
      [for (var p = 0; p < players; p++) p]
          .every((p) => doneRating.contains(p) || toRate(p).isEmpty);

  List<int> winners() {
    if (scores.isEmpty) return [];
    final best = scores.reduce(max);
    return [
      for (var p = 0; p < players; p++)
        if (scores[p] == best) p,
    ];
  }
}
