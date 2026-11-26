import 'dart:math';

import 'package:flutter/material.dart';

import '../core/companion.dart';

/// Web Mercator: world coordinates 0..256 at zoom 0.
Offset mercator(double lat, double lng) {
  final l = lat.clamp(-85.05, 85.05) * pi / 180;
  return Offset(
    (lng + 180) / 360 * 256,
    (1 - log(tan(l) + 1 / cos(l)) / pi) / 2 * 256,
  );
}

(double, double) fromMercator(Offset w) {
  final lng = w.dx / 256 * 360 - 180;
  final n = pi * (1 - 2 * w.dy / 256);
  final lat = atan((exp(n) - exp(-n)) / 2) * 180 / pi;
  return (lat, ((lng + 180) % 360) - 180);
}

/// A small slippy map for the lower screen: raster tiles (no web view, the
/// lower screen's engine runs without plugins), drag and pinch to move and
/// zoom, tap to place a pin, pins and lines of the round's result.
class CompanionMapView extends StatefulWidget {
  const CompanionMapView({
    super.key,
    required this.map,
    required this.onAction,
    this.tileUrl = defaultTiles,
  });

  final CompanionMap map;
  final void Function(String action) onAction;

  /// Raster tiles with {s} (subdomain), {z}, {x}, {y}.
  final String tileUrl;

  static const defaultTiles =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  @override
  State<CompanionMapView> createState() => _CompanionMapViewState();
}

class _CompanionMapViewState extends State<CompanionMapView> {
  static const _minZoom = 1.0, _maxZoom = 17.0;

  /// View centre in world coordinates and zoom level.
  Offset _center = const Offset(128, 110);
  double _zoom = 1.3;
  (double, double)? _pin;
  Size _size = Size.zero;

  // Gesture state.
  Offset? _startCenter, _startFocal;
  double _startZoom = 1;

  @override
  void didUpdateWidget(CompanionMapView old) {
    super.didUpdateWidget(old);
    if (old.map.id != widget.map.id) {
      _pin = null;
      _fitted = false;
    }
  }

  bool _fitted = false;

  /// Shows all pins of a result at once.
  void _fit() {
    if (_fitted || _size == Size.zero) return;
    _fitted = true;
    final pins = widget.map.pins;
    if (pins.isEmpty) {
      _center = const Offset(128, 110);
      _zoom = log(max(_size.width, _size.height) / 256) / ln2 + 0.2;
      _zoom = _zoom.clamp(_minZoom, 3.0);
      return;
    }
    final pts = [for (final p in pins) mercator(p.lat, p.lng)];
    var rect = Rect.fromPoints(pts.first, pts.first);
    for (final p in pts) {
      rect = rect.expandToInclude(Rect.fromPoints(p, p));
    }
    _center = rect.center;
    final w = max(rect.width, 0.0005), h = max(rect.height, 0.0005);
    final z = min(
      log((_size.width * 0.75) / w) / ln2,
      log((_size.height * 0.75) / h) / ln2,
    );
    _zoom = z.clamp(_minZoom, 12.0);
  }

  double get _scale => pow(2, _zoom).toDouble();

  Offset _toScreen(Offset world) =>
      (world - _center) * _scale + _size.center(Offset.zero);

  Offset _toWorld(Offset screen) =>
      (screen - _size.center(Offset.zero)) / _scale + _center;

  void _zoomAt(Offset focal, double zoom) {
    final before = _toWorld(focal);
    _zoom = zoom.clamp(_minZoom, _maxZoom);
    final after = _toWorld(focal);
    _center += before - after;
    _clamp();
  }

  void _clamp() {
    _center = Offset(_center.dx % 256, _center.dy.clamp(0.0, 256.0));
  }

  String _url(int z, int x, int y) {
    const subs = ['a', 'b', 'c', 'd'];
    return widget.tileUrl
        .replaceAll('{s}', subs[(x + y) % 4])
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }

  List<Widget> _tiles() {
    final z = _zoom.floor().clamp(0, 18);
    final n = 1 << z;
    final tile = 256 * pow(2, _zoom - z).toDouble();
    final topLeft = _toWorld(Offset.zero) * n.toDouble() / 256;
    final x0 = topLeft.dx.floor(), y0 = max(0, topLeft.dy.floor());
    final cols = (_size.width / tile).ceil() + 1;
    final rows = (_size.height / tile).ceil() + 1;
    return [
      for (var ty = y0; ty < min(n, y0 + rows + 1); ty++)
        for (var tx = x0; tx < x0 + cols + 1; tx++)
          Positioned(
            left: _toScreen(Offset(tx * 256 / n, 0)).dx,
            top: _toScreen(Offset(0, ty * 256 / n)).dy,
            width: tile + 0.5,
            height: tile + 0.5,
            child: Image.network(
              _url(z, tx % n, ty),
              key: ValueKey('$z/${tx % n}/$ty'),
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const ColoredBox(color: _sea),
            ),
          ),
    ];
  }

  static const _sea = Color(0xFFAAD3DF);

  @override
  Widget build(BuildContext context) {
    final map = widget.map;
    final pick = map.pickAction;
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        _fit();
        final pins = [
          for (final p in map.pins) (_toScreen(mercator(p.lat, p.lng)), p),
        ];
        final own = _pin;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _sea)),
              GestureDetector(
                key: const ValueKey('companionMap'),
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _startCenter = _center;
                  _startFocal = d.localFocalPoint;
                  _startZoom = _zoom;
                },
                onScaleUpdate: (d) => setState(() {
                  _center = _startCenter!;
                  _zoom = _startZoom;
                  _zoomAt(_startFocal!, _startZoom + log(d.scale) / ln2);
                  _center -= (d.localFocalPoint - _startFocal!) / _scale;
                  _clamp();
                }),
                onTapUp: pick == null
                    ? null
                    : (d) => setState(
                        () => _pin = fromMercator(_toWorld(d.localPosition)),
                      ),
                onDoubleTapDown: (d) => _startFocal = d.localPosition,
                onDoubleTap: () => setState(
                  () => _zoomAt(
                    _startFocal ?? _size.center(Offset.zero),
                    _zoom + 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ..._tiles(),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LinesPainter([
                          if (map.lineTo case final t?
                              when t >= 0 && t < pins.length)
                            for (final (i, p) in pins.indexed)
                              if (i != t) (p.$1, pins[t].$1),
                        ]),
                      ),
                    ),
                    for (final (pos, p) in pins) _marker(pos, p.label, p.color),
                    if (own != null)
                      _marker(
                        _toScreen(mercator(own.$1, own.$2)),
                        'Mein Tipp',
                        0xFF1E88E5,
                      ),
                  ],
                ),
              ),
              // Zoom buttons and attribution.
              Positioned(
                right: 6,
                top: 6,
                child: Column(
                  children: [
                    _zoomButton(Icons.add, 1),
                    const SizedBox(height: 4),
                    _zoomButton(Icons.remove, -1),
                  ],
                ),
              ),
              const Positioned(
                left: 4,
                bottom: 2,
                child: Text(
                  '© OpenStreetMap · © CARTO',
                  style: TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
              if (pick != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: Center(
                    child: own == null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Tippe auf die Karte, wo das Bild sein könnte',
                              style: TextStyle(color: Colors.white),
                            ),
                          )
                        : FilledButton.icon(
                            key: const ValueKey('companionMapPick'),
                            onPressed: () => widget.onAction(
                              '$pick:${own.$1.toStringAsFixed(5)},'
                              '${own.$2.toStringAsFixed(5)}',
                            ),
                            icon: const Icon(Icons.place),
                            label: Text(map.pickLabel),
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _zoomButton(IconData icon, double step) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 2,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () =>
          setState(() => _zoomAt(_size.center(Offset.zero), _zoom + step)),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 20, color: Colors.black87),
      ),
    ),
  );

  Widget _marker(Offset pos, String label, int? color) => Positioned(
    left: pos.dx - 60,
    top: pos.dy - 46,
    width: 120,
    child: IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
          Icon(
            Icons.location_on,
            size: 28,
            color: Color(color ?? 0xFFE53935),
            shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
          ),
        ],
      ),
    ),
  );
}

class _LinesPainter extends CustomPainter {
  const _LinesPainter(this.lines);
  final List<(Offset, Offset)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2;
    for (final (a, b) in lines) {
      // Dashed, like on the map above.
      final d = b - a;
      final len = d.distance;
      if (len < 1) continue;
      final step = d / len;
      for (var s = 0.0; s < len; s += 10) {
        canvas.drawLine(a + step * s, a + step * min(s + 6, len), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}
