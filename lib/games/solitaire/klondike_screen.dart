import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/leaderboard.dart';
import '../../ui/leaderboard_screen.dart';
import 'card_cascade.dart';
import 'klondike_logic.dart';

class _Drag {
  const _Drag(this.from, this.index);
  final PileRef from;
  final int index;
}

class KlondikeScreen extends StatefulWidget {
  const KlondikeScreen({super.key});

  @override
  State<KlondikeScreen> createState() => _KlondikeScreenState();
}

class _KlondikeScreenState extends State<KlondikeScreen> {
  int drawCount = 1;
  late KlondikeGame game = KlondikeGame(drawCount: drawCount);
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  bool _autoRunning = false;
  bool _wonShown = false;
  int wins = 0;
  int best = 0;
  int bonus = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        wins = p.getInt('klondike.wins') ?? 0;
        best = p.getInt('klondike.best') ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newGame() {
    setState(() {
      game = KlondikeGame(drawCount: drawCount);
      _wonShown = false;
      bonus = 0;
      _clock
        ..reset()
        ..start();
    });
  }

  void _after() {
    if (game.won && !_wonShown) {
      _wonShown = true;
      _clock.stop();
      _celebrate();
    }
  }

  final GlobalKey _bodyKey = GlobalKey();
  final List<GlobalKey> _foundationKeys = List.generate(4, (_) => GlobalKey());

  /// Cards of the win animation, null while it doesn't run.
  List<CascadeCard>? _cascade;

  /// Cards per foundation that already flew off.
  final List<int> _flown = List.filled(4, 0);
  List<int> _cascadeFrom = const [];

  /// Starts the victory animation; completes when it is over.
  Future<void> _playCascade() async {
    final body = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (body == null) return;
    final starts = [
      for (final k in _foundationKeys)
        body.globalToLocal(
          (k.currentContext!.findRenderObject() as RenderBox).localToGlobal(
            Offset.zero,
          ),
        ),
    ];
    // Kings first, round the four piles, like the original.
    final cards = <CascadeCard>[];
    final from = <int>[];
    for (var rank = 12; rank >= 0; rank--) {
      for (var f = 0; f < 4; f++) {
        if (rank < game.foundations[f].length) {
          cards.add(CascadeCard(game.foundations[f][rank], starts[f]));
          from.add(f);
        }
      }
    }
    final done = Completer<void>();
    setState(() {
      _flown.fillRange(0, 4, 0);
      _cascadeFrom = from;
      _cascade = cards;
      _cascadeDone = done;
    });
    await done.future;
  }

  Completer<void>? _cascadeDone;

  Widget _cascadeOverlay() => CardCascade(
    cards: _cascade!,
    cardWidth: _cardWidth,
    onLaunch: (i) => setState(() => _flown[_cascadeFrom[i]]++),
    onDone: () {
      setState(() => _cascade = null);
      _cascadeDone?.complete();
      _cascadeDone = null;
    },
  );

  double _cardWidth = 60;

  Future<void> _celebrate() async {
    bonus = KlondikeGame.timeBonus(_clock.elapsed.inSeconds);
    final total = game.score + bonus;
    final record = total > best;
    if (record) best = total;
    final p = await SharedPreferences.getInstance();
    wins++;
    await p.setInt('klondike.wins', wins);
    await p.setInt('klondike.best', best);
    await Leaderboard.submit('klondike', total);
    if (!mounted) return;
    setState(() {});
    await _playCascade();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Gewonnen! 🎉'),
        content: Text(
          'Punkte: ${game.score} + $bonus Zeitbonus = $total'
          '${record ? ' – neuer Rekord!' : ''}\n'
          '${game.moves} Züge in ${_time()}.\nGewonnene Spiele: $wins',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              _newGame();
            },
            child: const Text('Neues Spiel'),
          ),
        ],
      ),
    );
  }

  String _time() {
    final s = _clock.elapsed.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _tap(PileRef from, int index) {
    if (_autoRunning) return;
    final to = game.bestTarget(from, index);
    if (to == null) {
      HapticFeedback.selectionClick();
      return;
    }
    setState(() => game.move(from, index, to));
    _after();
  }

  void _drop(_Drag d, PileRef to) {
    setState(() => game.move(d.from, d.index, to));
    _after();
  }

  Future<void> _autoComplete() async {
    setState(() => _autoRunning = true);
    while (mounted && game.autoStep()) {
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (mounted) setState(() => _autoRunning = false);
    _after();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('Solitär'),
        actions: [
          const LeaderboardButton(game: 'klondike'),
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: game.canUndo && !_autoRunning
                ? () => setState(game.undo)
                : null,
            icon: const Icon(Icons.undo),
          ),
          PopupMenuButton<int>(
            tooltip: 'Neues Spiel',
            icon: const Icon(Icons.refresh),
            onSelected: (n) {
              drawCount = n;
              _newGame();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 1,
                child: Text('Neues Spiel – 1 Karte ziehen'),
              ),
              PopupMenuItem(
                value: 3,
                child: Text('Neues Spiel – 3 Karten ziehen'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        key: _bodyKey,
        children: [
          SafeArea(child: _table()),
          if (_cascade != null) Positioned.fill(child: _cascadeOverlay()),
        ],
      ),
    );
  }

  Widget _table() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = min((min(c.maxWidth, 900) - 8 * 6) / 7, 110.0);
        _cardWidth = w;
        final h = w * 1.4;
        return Center(
          child: SizedBox(
            width: w * 7 + 8 * 6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Punkte: ${game.score + bonus}   •   '
                    'Züge: ${game.moves}   •   Zeit: ${_time()}'
                    '${best > 0 ? '   •   Rekord: $best' : ''}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                _topRow(w, h),
                const SizedBox(height: 12),
                Expanded(child: _tableauRow(w, h)),
                if (game.canAutoComplete)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: FilledButton.icon(
                      key: const ValueKey('autoComplete'),
                      onPressed: _autoRunning ? null : _autoComplete,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Automatisch ablegen'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topRow(double w, double h) {
    final wasteShown = game.waste.length <= drawCount
        ? game.waste
        : game.waste.sublist(game.waste.length - min(drawCount, 3));
    return SizedBox(
      height: h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const ValueKey('stock'),
            onTap: _autoRunning ? null : () => setState(game.draw),
            child: game.stock.isEmpty
                ? _emptySlot(w, h, Icons.refresh)
                : _CardView(card: game.stock.last, width: w),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: w * 2 + 8,
            height: h,
            child: Stack(
              children: [
                if (wasteShown.isEmpty) _emptySlot(w, h, null),
                for (var i = 0; i < wasteShown.length; i++)
                  Positioned(
                    left: i * w * 0.32,
                    child: i == wasteShown.length - 1
                        ? _draggable(
                            const PileRef(PileKind.waste),
                            game.waste.length - 1,
                            [wasteShown[i]],
                            w,
                          )
                        : _CardView(card: wasteShown[i], width: w),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (var f = 0; f < 4; f++) ...[
            if (f > 0) const SizedBox(width: 8),
            KeyedSubtree(
              key: _foundationKeys[f],
              child: _target(
                PileRef(PileKind.foundation, f),
                w,
                h,
                child: _foundation(f, w, h),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _foundation(int f, double w, double h) {
    final pile = game.foundations[f];
    // During the win animation the flown cards are gone.
    final shown = _cascade == null ? pile.length : pile.length - _flown[f];
    if (shown <= 0) return _emptySlot(w, h, null, label: 'A');
    if (_cascade != null) return _CardView(card: pile[shown - 1], width: w);
    return _draggable(PileRef(PileKind.foundation, f), pile.length - 1, [
      pile.last,
    ], w);
  }

  Widget _tableauRow(double w, double h) {
    return LayoutBuilder(
      builder: (context, c) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var t = 0; t < 7; t++) ...[
            if (t > 0) const SizedBox(width: 8),
            _target(
              PileRef(PileKind.tableau, t),
              w,
              c.maxHeight,
              child: _column(t, w, h, c.maxHeight),
            ),
          ],
        ],
      ),
    );
  }

  Widget _column(int t, double w, double h, double maxHeight) {
    final cards = game.tableau[t];
    if (cards.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: _emptySlot(w, h, null, label: 'K'),
      );
    }
    // Overlap: smaller steps for closed cards; squeeze if the pile is long.
    var closed = h * 0.12, open = h * 0.28;
    final needed =
        cards.fold<double>(0, (a, c) => a + (c.faceUp ? open : closed)) + h;
    if (needed > maxHeight) {
      final f = (maxHeight - h) / (needed - h);
      closed *= f;
      open *= f;
    }
    final children = <Widget>[];
    var y = 0.0;
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      children.add(
        Positioned(
          top: y,
          child: card.faceUp
              ? _draggable(
                  PileRef(PileKind.tableau, t),
                  i,
                  cards.sublist(i),
                  w,
                  step: open,
                )
              : _CardView(card: card, width: w),
        ),
      );
      y += card.faceUp ? open : closed;
    }
    return SizedBox(
      width: w,
      height: maxHeight,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  Widget _draggable(
    PileRef from,
    int index,
    List<PlayingCard> run,
    double w, {
    double? step,
  }) {
    final s = step ?? w * 0.4;
    Widget stack(double opacity) => SizedBox(
      width: w,
      height: w * 1.4 + s * (run.length - 1),
      child: Stack(
        children: [
          for (var i = 0; i < run.length; i++)
            Positioned(
              top: i * s,
              child: Opacity(
                opacity: opacity,
                child: _CardView(card: run[i], width: w),
              ),
            ),
        ],
      ),
    );
    return Draggable<_Drag>(
      data: _Drag(from, index),
      maxSimultaneousDrags: _autoRunning ? 0 : 1,
      feedback: Material(color: Colors.transparent, child: stack(1)),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _CardView(card: run.first, width: w),
      ),
      child: GestureDetector(
        key: ValueKey('card-${run.first.suit}-${run.first.rank}'),
        onTap: () => _tap(from, index),
        child: _CardView(card: run.first, width: w),
      ),
    );
  }

  Widget _target(PileRef to, double w, double h, {required Widget child}) {
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) =>
          game.canMove(d.data.from, d.data.index, to),
      onAcceptWithDetails: (d) => _drop(d.data, to),
      builder: (context, candidate, _) => Container(
        decoration: candidate.isNotEmpty
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Colors.yellowAccent, blurRadius: 8),
                ],
              )
            : null,
        child: SizedBox(width: w, height: h, child: child),
      ),
    );
  }

  Widget _emptySlot(double w, double h, IconData? icon, {String? label}) =>
      Container(
        width: w,
        height: w * 1.4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.08),
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, color: Colors.white54, size: w * 0.4)
              : Text(
                  label ?? '',
                  style: TextStyle(color: Colors.white24, fontSize: w * 0.35),
                ),
        ),
      );
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card, required this.width});
  final PlayingCard card;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final radius = BorderRadius.circular(width * 0.08);
    if (!card.faceUp) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white, width: 2),
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.diamond_outlined,
            color: Colors.white24,
            size: width * 0.5,
          ),
        ),
      );
    }
    final color = card.red ? const Color(0xFFD32F2F) : Colors.black;
    // ︎ asks for the text (not emoji) form of the suit symbol.
    final suit = '${card.suitSymbol}︎';
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: Colors.black26),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      padding: EdgeInsets.all(width * 0.05),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Text(
              '${card.rankLabel}$suit',
              style: TextStyle(
                color: color,
                fontSize: width * 0.26,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.4),
            child: Text(
              suit,
              style: TextStyle(color: color, fontSize: width * 0.5, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}
