import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geobingo_logic.dart';
import 'street_view_io.dart'
    if (dart.library.js_interop) 'street_view_web.dart'
    as platform;

/// Keys from the build (`--dart-define`); without one the source is off.
const googleMapsKey = String.fromEnvironment('GOOGLE_MAPS_KEY');
const mapillaryToken = String.fromEnvironment('MAPILLARY_TOKEN');

String keyFor(GeoSource s) => switch (s) {
  GeoSource.google => googleMapsKey,
  GeoSource.mapillary => mapillaryToken,
};

/// Sources this build has a key for.
List<GeoSource> get availableSources => [
  for (final s in GeoSource.values)
    if (keyFor(s).isNotEmpty) s,
];

/// The page is loaded as if it came from the web app, so one key
/// restricted to that address works in the app and in the browser.
const viewerBaseUrl = 'https://sommer2019.github.io/MobileGames/';

/// Whether street pictures can be shown on this device.
bool get streetViewSupported => platform.supported;

enum StreetViewMode { hunt, show }

/// Talks to the street picture page (assets/geobingo/viewer.html).
class StreetViewController extends ChangeNotifier {
  void Function(String json)? _post;
  final List<String> _queue = [];
  final Map<int, Completer<(GeoView?, String?)>> _marks = {};
  int _req = 0;

  bool ready = false;
  String? error;

  /// The view the player looks at now: (view, null) or (null, why not).
  Future<(GeoView?, String?)> mark() {
    final c = Completer<(GeoView?, String?)>();
    final id = ++_req;
    _marks[id] = c;
    _send({'t': 'mark', 'req': id});
    return c.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => (null, 'Keine Antwort von Street View'),
    );
  }

  /// Shows a marked view (review).
  void show(GeoView v) => _send({'t': 'show', 'view': v.toJson()});

  void _send(Map<String, dynamic> m) {
    final json = jsonEncode(m);
    final post = _post;
    if (post == null || !ready && m['t'] != 'init') {
      _queue.add(json);
    } else {
      post(json);
    }
  }

  /// Called by the platform view with the page's messages.
  @visibleForTesting
  void handle(String json, Map<String, dynamic> init) {
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
      case 'marked':
        final c = _marks.remove(m['req']);
        if (c == null || c.isCompleted) return;
        final v = GeoView.fromJson(m['view']);
        c.complete(v == null ? (null, '${m['error'] ?? 'Fehler'}') : (v, null));
    }
  }
}

/// Street pictures in the app: a web view on phones and Macs, an iframe in
/// the browser.
class StreetView extends StatefulWidget {
  const StreetView({
    super.key,
    required this.controller,
    required this.source,
    required this.mode,
  });

  final StreetViewController controller;
  final GeoSource source;
  final StreetViewMode mode;

  @override
  State<StreetView> createState() => _StreetViewState();
}

class _StreetViewState extends State<StreetView> {
  String? _html;

  Map<String, dynamic> get _init => {
    't': 'init',
    'source': widget.source.name,
    'key': keyFor(widget.source),
    'mode': widget.mode.name,
  };

  @override
  void initState() {
    super.initState();
    if (streetViewSupported) {
      rootBundle.loadString('assets/geobingo/viewer.html').then((h) {
        if (mounted) setState(() => _html = h);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!streetViewSupported) {
      return const _Message(
        'Street View gibt es hier nicht.\n'
        'Spiel Geobingo am Handy, auf dem Mac oder im Browser.',
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
        onMessage: (m) => widget.controller.handle(m, _init),
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
