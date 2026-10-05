import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/net/room.dart';
import '../core/sound.dart';
import 'confetti.dart';

/// Cheers of players and spectators: emojis float up over the game, 🎉
/// also rains confetti.
class ReactionOverlay extends StatefulWidget {
  const ReactionOverlay({super.key, required this.room, required this.child});
  final GameRoom room;
  final Widget child;

  @override
  State<ReactionOverlay> createState() => _ReactionOverlayState();
}

class _Flying {
  _Flying(this.reaction, this.x, this.key);
  final Reaction reaction;
  final double x;
  final Key key;
}

class _ReactionOverlayState extends State<ReactionOverlay> {
  final List<_Flying> _flying = [];
  final Random _random = Random();
  StreamSubscription<Reaction>? _sub;
  bool _confetti = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.room.reactions.listen(_add);
  }

  void _add(Reaction r) {
    if (!mounted) return;
    Sound.play(Sfx.click, volume: 0.4);
    final f = _Flying(r, 0.1 + _random.nextDouble() * 0.8, ValueKey(_count++));
    setState(() {
      _flying.add(f);
      if (_flying.length > 20) _flying.removeAt(0);
      if (r.emoji == '🎉') _confetti = true;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_confetti)
          Positioned.fill(
            child: IgnorePointer(
              child: Confetti(
                key: const ValueKey('reactionConfetti'),
                pieces: 80,
                onDone: () => setState(() => _confetti = false),
              ),
            ),
          ),
        for (final f in _flying)
          Positioned.fill(
            key: f.key,
            child: IgnorePointer(
              child: _FlyingEmoji(
                flying: f,
                onDone: () => setState(() => _flying.remove(f)),
              ),
            ),
          ),
      ],
    );
  }
}

class _FlyingEmoji extends StatefulWidget {
  const _FlyingEmoji({required this.flying, required this.onDone});
  final _Flying flying;
  final VoidCallback onDone;

  @override
  State<_FlyingEmoji> createState() => _FlyingEmojiState();
}

class _FlyingEmojiState extends State<_FlyingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final x = widget.flying.x * box.maxWidth + sin(t * 2 * pi) * 18 - 30;
          final y = box.maxHeight * (0.85 - 0.75 * t);
          return Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                child: Opacity(
                  opacity: t < 0.75 ? 1 : (1 - t) * 4,
                  child: Column(
                    children: [
                      Text(
                        widget.flying.reaction.emoji,
                        style: TextStyle(fontSize: 40 + 10 * sin(t * pi)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.flying.reaction.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Row of cheer buttons.
class ReactionBar extends StatefulWidget {
  const ReactionBar({super.key, required this.onReact});
  final void Function(String emoji) onReact;

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  DateTime _last = DateTime(2000);

  void _tap(String e) {
    // At most a few cheers per second.
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 400)) return;
    _last = now;
    widget.onReact(e);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in GameRoom.reactionEmojis)
          IconButton(
            key: ValueKey('react$e'),
            tooltip: 'Jubeln',
            onPressed: () => _tap(e),
            icon: Text(e, style: const TextStyle(fontSize: 24)),
          ),
      ],
    );
  }
}
