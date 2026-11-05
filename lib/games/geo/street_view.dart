import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geo_view.dart';
import 'street_view_io.dart'
    if (dart.library.js_interop) 'street_view_web.dart'
    as platform;

/// Keys from the build (`--dart-define`); without one the source is off.
const googleMapsKey = String.fromEnvironment('GOOGLE_MAPS_KEY');
const mapillaryToken = String.fromEnvironment('MAPILLARY_TOKEN');

String keyFor(GeoSource s) => switch (s) {
  GeoSource.google => googleMapsKey,
  GeoSource.mapillary => mapillaryToken,
  GeoSource.panoramax => '',
};

/// Sources this build can use (with a key where one is needed).
List<GeoSource> get availableSources => [
  for (final s in GeoSource.values)
    if (!s.needsKey || keyFor(s).isNotEmpty) s,
];

/// The free sources this build can use, or Google alone without them.
List<GeoSource> get defaultSources {
  final free = availableSources.where((s) => s != GeoSource.google).toList();
  return free.isEmpty ? [GeoSource.google] : free;
}

/// The page is loaded as if it came from the web app, so one key
/// restricted to that address works in the app and in the browser.
const viewerBaseUrl = 'https://sommer2019.github.io/MobileGames/';

/// Whether street pictures can be shown on this device.
bool get streetViewSupported => platform.supported;

/// hunt: walk around and mark views; show: look at a marked view;
/// guess: look at a view and tap a guess on a map.
enum StreetViewMode { hunt, show, guess }

/// A point on the result map of a guessing round.
class MapPin {
  const MapPin(this.lat, this.lng, this.label);
  final double lat;
  final double lng;
  final String label;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'label': label};
}

/// Talks to the street picture page (assets/geo/viewer.html).
class StreetViewController extends ChangeNotifier {
  void Function(String json)? _post;
  final List<String> _queue = [];
  final Map<int, Completer<Map>> _requests = {};
  int _req = 0;

  bool ready = false;
  String? error;

  Future<Map> _ask(Map<String, dynamic> m, Duration timeout) {
    final c = Completer<Map>();
    final id = ++_req;
    _requests[id] = c;
    _send({...m, 'req': id});
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _requests.remove(id);
        return {'error': 'Keine Antwort von der Bildseite'};
      },
    );
  }

  /// The view the player looks at now: (view, null) or (null, why not).
  Future<(GeoView?, String?)> mark() async {
    final r = await _ask({'t': 'mark'}, const Duration(seconds: 15));
    final v = GeoView.fromJson(r['view']);
    return v == null ? (null, '${r['error'] ?? 'Fehler'}') : (v, null);
  }

  /// The place the player tapped on the guess map, or (null, why not).
  Future<((double, double)?, String?)> guess() async {
    final r = await _ask({'t': 'guess'}, const Duration(seconds: 5));
    final lat = r['lat'], lng = r['lng'];
    if (lat is num && lng is num) {
      return ((lat.toDouble(), lng.toDouble()), null);
    }
    return (null, '${r['error'] ?? 'Fehler'}');
  }

  /// A random picture from one of [sources] (guessing rounds).
  Future<(GeoView?, String?)> random(List<GeoSource> sources) async {
    final r = await _ask({
      't': 'random',
      'sources': [for (final s in sources) s.name],
    }, const Duration(seconds: 60));
    final v = GeoView.fromJson(r['view']);
    return v == null
        ? (null, '${r['error'] ?? 'Kein Ort gefunden'}')
        : (v, null);
  }

  /// Shows a view (review, guessing round).
  void show(GeoView v) => _send({'t': 'show', 'view': v.toJson()});

  /// Shows the right place and everybody's guesses on the map.
  void result(MapPin truth, List<MapPin> guesses) => _send({
    't': 'result',
    'truth': truth.toJson(),
    'guesses': [for (final g in guesses) g.toJson()],
  });

  void _send(Map<String, dynamic> m) {
    final json = jsonEncode(m);
    final post = _post;
    if (post == null || !ready) {
      _queue.add(json);
    } else {
      post(json);
    }
  }

  void _handle(String json, Map<String, dynamic> init) {
    final Object? m;
    try {
      m = jsonDecode(json);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    switch (m['t']) {
      case 'loaded':
        _post?.call(jsonEncode(init));
      case 'ready':
        ready = true;
        error = null;
        for (final q in _queue) {
          _post?.call(q);
        }
        _queue.clear();
        notifyListeners();
      case 'error':
        error = '${m['msg'] ?? 'Fehler'}';
        notifyListeners();
      case 'reply':
        final c = _requests.remove(m['req']);
        if (c != null && !c.isCompleted) c.complete(m);
    }
  }
}

/// Street pictures in the app: a web view on phones and Macs, an iframe in
/// the browser.
class StreetView extends StatefulWidget {
  const StreetView({
    super.key,
    required this.controller,
    required this.sources,
    required this.mode,
  });

  final StreetViewController controller;
  final List<GeoSource> sources;
  final StreetViewMode mode;

  @override
  State<StreetView> createState() => _StreetViewState();
}

class _StreetViewState extends State<StreetView> {
  String? _html;

  Map<String, dynamic> get _init => {
    't': 'init',
    'sources': [for (final s in widget.sources) s.name],
    'keys': {for (final s in availableSources) s.name: keyFor(s)},
    'mode': widget.mode.name,
  };

  @override
  void initState() {
    super.initState();
    if (streetViewSupported) {
      rootBundle.loadString('assets/geo/viewer.html').then((h) {
        if (mounted) setState(() => _html = h);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!streetViewSupported) {
      return const _Message(
        'Street View gibt es hier nicht.\n'
        'Spiel am Handy, auf dem Mac oder im Browser.',
      );
    }
    final html = _html;
    if (html == null) return const Center(child: CircularProgressIndicator());
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) => Stack(
        children: [
          Positioned.fill(child: child!),
          if (widget.controller.error case final e?)
            Positioned.fill(child: _Message(e)),
        ],
      ),
      child: platform.buildView(
        html: html,
        baseUrl: viewerBaseUrl,
        onMessage: (m) => widget.controller._handle(m, _init),
        attach: (post) => widget.controller._post = post,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
}
