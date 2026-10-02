import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'klondike_logic.dart';

/// A card that leaves a foundation in the win animation.
class CascadeCard {
  CascadeCard(this.card, this.start);
  final PlayingCard card;

  /// Top left corner of the foundation it starts from (local coordinates
  /// of the [CardCascade]).
  final Offset start;
}

/// The classic solitaire victory: cards jump off the foundations one after
/// another, bounce over the table and leave a trail of copies behind.
class CardCascade extends StatefulWidget {
  const CardCascade({
    super.key,
    required this.cards,
    required this.cardWidth,
    required this.onLaunch,
    required this.onDone,
    this.interval = const Duration(milliseconds: 320),
    this.seed,
  });

  /// In launch order.
  final List<CascadeCard> cards;
  final double cardWidth;

  /// Called when card [index] leaves its foundation.
  final ValueChanged<int> onLaunch;

  /// Called after the last card left the screen, or on a tap.
  final VoidCallback onDone;
  final Duration interval;
  final int? seed;

  @override
  State<CardCascade> createState() => _CardCascadeState();
}

class _Flying {
  _Flying(this.index, this.x, this.y, this.vx, this.vy);
  final int index;
  double x, y, vx, vy;
}

class _CardCascadeState extends State<CardCascade>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final Random _random = Random(widget.seed);
  final List<_Flying> _flying = [];
  final Map<int, ui.Picture> _pictures = {};
  ui.Image? _trail;
  Size _size = Size.zero;
  double _dpr = 1;
  Duration _last = Duration.zero;
  Duration _sinceLaunch = Duration.zero;
  int _next = 0;
  bool _done = false;

  static const double gravity = 1600; // px/s²
  static const double bounce = 0.72;

  double get _w => widget.cardWidth;
  double get _h => widget.cardWidth * 1.4;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _trail?.dispose();
    for (final p in _pictures.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.onDone();
  }

  void _launch() {
    final i = _next++;
    final c = widget.cards[i];
    final dir = _random.nextBool() ? 1.0 : -1.0;
    _flying.add(
      _Flying(
        i,
        c.start.dx,
        c.start.dy,
        dir * (180 + _random.nextDouble() * 320),
        -(_random.nextDouble() * 500),
      ),
    );
    widget.onLaunch(i);
  }

  void _tick(Duration now) {
    if (_size.isEmpty) return;
    final dt = _last == Duration.zero
        ? 0.0
        : min((now - _last).inMicroseconds / 1e6, 0.05);
    _last = now;
    _sinceLaunch += Duration(microseconds: (dt * 1e6).round());
    if (_next < widget.cards.length &&
        (_next == 0 || _sinceLaunch >= widget.interval)) {
      _sinceLaunch = Duration.zero;
      _launch();
    }
    // Several small steps per frame keep the trail dense.
    const steps = 3;
    final h = dt / steps;
    final stamps = <_Flying>[];
    for (var s = 0; s < steps; s++) {
      for (final f in _flying) {
        f.vy += gravity * h;
        f.x += f.vx * h;
        f.y += f.vy * h;
        if (f.y + _h > _size.height) {
          f.y = _size.height - _h;
          f.vy = -f.vy * bounce;
        }
        stamps.add(_Flying(f.index, f.x, f.y, 0, 0));
      }
    }
    _flying.removeWhere((f) => f.x + _w < 0 || f.x > _size.width);
    _stamp(stamps);
    if (_next >= widget.cards.length && _flying.isEmpty) {
      _finish();
      return;
    }
    setState(() {});
  }

  /// Draws the cards at their new positions on top of the trail.
  void _stamp(List<_Flying> stamps) {
    if (stamps.isEmpty) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_dpr);
    final old = _trail;
    if (old != null) {
      canvas.save();
      canvas.scale(1 / _dpr);
      canvas.drawImage(old, Offset.zero, Paint());
      canvas.restore();
    }
    for (final s in stamps) {
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.drawPicture(_picture(s.index));
      canvas.restore();
    }
    final picture = recorder.endRecording();
    _trail = picture.toImageSync(
      (_size.width * _dpr).ceil(),
      (_size.height * _dpr).ceil(),
    );
    picture.dispose();
    old?.dispose();
  }

  ui.Picture _picture(int index) => _pictures.putIfAbsent(index, () {
    final recorder = ui.PictureRecorder();
    paintCardFace(Canvas(recorder), widget.cards[index].card, _w);
    return recorder.endRecording();
  });

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        return GestureDetector(
          key: const ValueKey('cardCascade'),
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: CustomPaint(
            size: c.biggest,
            painter: _TrailPainter(_trail, _dpr),
          ),
        );
      },
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.image, this.dpr);
  final ui.Image? image;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) return;
    canvas.save();
    canvas.scale(1 / dpr);
    canvas.drawImage(img, Offset.zero, Paint());
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrailPainter old) => true;
}

/// Paints a face-up card like the card widgets of the game, with its top
/// left corner at the origin.
void paintCardFace(Canvas canvas, PlayingCard card, double w) {
  final h = w * 1.4;
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, w, h),
    Radius.circular(w * 0.08),
  );
  canvas.drawRRect(rect, Paint()..color = Colors.white);
  canvas.drawRRect(
    rect,
    Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  final color = card.red ? const Color(0xFFD32F2F) : Colors.black;
  final suit = '${card.suitSymbol}︎';
  void text(String s, double size, Offset at, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  text('${card.rankLabel}$suit', w * 0.26, Offset(w * 0.05, w * 0.05));
  text(suit, w * 0.5, Offset(w / 2, h * 0.62), center: true);
}
