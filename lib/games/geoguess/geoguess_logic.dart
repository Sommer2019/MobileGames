import 'dart:math';

import '../geo/geo_view.dart';

export '../geo/geo_view.dart';

enum GuessPhase { setup, round, reveal, results }

/// Distance in km between two points (haversine).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

/// Points for a guess [km] away: 5000 on the spot, half at ~1400 km.
int pointsFor(double km) => km < 0.05 ? 5000 : (5000 * exp(-km / 2000)).round();

/// "Wo bin ich?": everybody sees the same street picture and guesses on a
/// map where it was taken; the closer, the more points.
///
/// Played through [apply] with plain events (seat of the sender given):
/// host only: `['cfg', {rounds, sec, src}]`, `['round', r, view, epochMs]`,
/// `['reveal', r, {seat: [lat, lng]}]`, `['end']`, `['new']`;
/// everybody: `['guess', r, lat, lng]`.
/// The host's `reveal` carries the guesses as the host has them, so every
/// device scores the same even when a late guess only reached some.
class GeoGuessGame {
  GeoGuessGame({required this.players, List<GeoSource>? sources})
    : sources = sources ?? [GeoSource.panoramax];

  static const maxRounds = 10;
  static const timeChoices = [0, 60, 120, 300];

  final int players;
  final List<List> events = [];

  GuessPhase phase = GuessPhase.setup;
  int rounds = 5;

  /// Seconds per round, 0 = no limit.
  int seconds = 0;
  List<GeoSource> sources;

  /// The pictures of the rounds so far.
  final List<GeoView> views = [];

  /// Host clock when the current round started.
  int startedAt = 0;

  /// round → seat → guessed point.
  final Map<int, Map<int, (double, double)>> guesses = {};

  int get round => views.length - 1;
  bool get isOver => phase == GuessPhase.results;
  bool get lastRound => views.length >= rounds;

  bool apply(List e, int seat) {
    final host = seat == 0;
    switch (e) {
      case ['cfg', final Map c] when host && phase == GuessPhase.setup:
        final r = c['rounds'], sec = c['sec'];
        final s = GeoSource.parseMix(c['src']);
        if (r is! int || r < 1 || r > maxRounds || s == null) return false;
        if (sec is! int || !timeChoices.contains(sec)) return false;
        rounds = r;
        seconds = sec;
        sources = s;
      case ['round', final int r, final Object? v, final int at]
          when host &&
              (phase == GuessPhase.setup || phase == GuessPhase.reveal) &&
              r == views.length &&
              r < rounds:
        final view = GeoView.fromJson(v);
        if (view == null || !sources.contains(view.source)) return false;
        views.add(view);
        startedAt = at;
        phase = GuessPhase.round;
      case ['guess', final int r, final num lat, final num lng]
          when phase == GuessPhase.round && r == round:
        if (lat.abs() > 90 || lng.abs() > 180 || seat >= players) return false;
        final mine = guesses[r] ??= {};
        if (mine.containsKey(seat)) return false;
        mine[seat] = (lat.toDouble(), lng.toDouble());
      case ['reveal', final int r, final Map g]
          when host && phase == GuessPhase.round && r == round:
        final all = <int, (double, double)>{};
        for (final MapEntry(:key, :value) in g.entries) {
          final s = int.tryParse('$key');
          if (s == null || s < 0 || s >= players || value is! List) continue;
          if (value.length != 2 || value.any((x) => x is! num)) continue;
          all[s] = ((value[0] as num).toDouble(), (value[1] as num).toDouble());
        }
        guesses[r] = all;
        phase = GuessPhase.reveal;
      case ['end'] when host && phase == GuessPhase.reveal && lastRound:
        phase = GuessPhase.results;
      case ['new'] when host && phase == GuessPhase.results:
        views.clear();
        guesses.clear();
        phase = GuessPhase.setup;
      default:
        return false;
    }
    events.add([seat, ...e]);
    return true;
  }

  factory GeoGuessGame.replay(int players, List log) {
    final g = GeoGuessGame(players: players);
    for (final x in log) {
      final l = List.from(x as List);
      g.apply(l.sublist(1), l.first as int);
    }
    return g;
  }

  /// Milliseconds left in the round (host clock), null without a limit.
  int? timeLeft(int now) =>
      seconds == 0 ? null : max(0, startedAt + seconds * 1000 - now);

  bool hasGuessed(int seat) => guesses[round]?.containsKey(seat) ?? false;

  bool get allGuessed =>
      [for (var p = 0; p < players; p++) p].every(hasGuessed);

  /// Distance of [seat]'s guess in round [r], null without a guess.
  double? distance(int r, int seat) {
    final g = guesses[r]?[seat];
    if (g == null || r >= views.length) return null;
    return distanceKm(g.$1, g.$2, views[r].lat, views[r].lng);
  }

  int roundPoints(int r, int seat) {
    final d = distance(r, seat);
    return d == null ? 0 : pointsFor(d);
  }

  /// Points of [seat] over the revealed rounds.
  int total(int seat) {
    final revealed = phase == GuessPhase.round ? round : views.length;
    var sum = 0;
    for (var r = 0; r < revealed; r++) {
      sum += roundPoints(r, seat);
    }
    return sum;
  }

  List<int> winners() {
    final best = [for (var p = 0; p < players; p++) total(p)].reduce(max);
    return [
      for (var p = 0; p < players; p++)
        if (total(p) == best) p,
    ];
  }
}

/// "1,2 km", "340 m", "12.345 km".
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  final s = km.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b km';
}
