import 'package:flutter/material.dart';

import '../core/services.dart';
import 'reactions.dart';

/// Over the whole app: who is watching our game, and their cheers for
/// games played on this device (online games show cheers in the game).
class WatchersOverlay extends StatelessWidget {
  const WatchersOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Services.isReady) return child;
    final hub = Services.I.spectators;
    return ReactionOverlay(
      reactions: hub.mirrorReactions,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 8,
            bottom: 8,
            child: IgnorePointer(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: hub.watcherNames,
                builder: (context, names, _) => names.isEmpty
                    ? const SizedBox.shrink()
                    : Material(
                        key: const ValueKey('watchersChip'),
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Text(
                            watchersText(names),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "👁 Anna schaut zu", "👁 Anna und Ben schauen zu", "👁 Anna, Ben und 2
/// weitere schauen zu".
String watchersText(List<String> names) {
  if (names.length == 1) return '👁 ${names.single} schaut zu';
  if (names.length <= 3) {
    return '👁 ${names.sublist(0, names.length - 1).join(', ')} und '
        '${names.last} schauen zu';
  }
  return '👁 ${names[0]}, ${names[1]} und ${names.length - 2} weitere '
      'schauen zu';
}
