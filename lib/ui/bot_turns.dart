import 'package:flutter/widgets.dart';

import 'bot_speed.dart';
import 'play_setup.dart';

/// Lets the computer players of a game move: offline every device plays
/// them, online only the host.
mixin BotTurns<T extends StatefulWidget> on State<T> {
  PlaySetup get setup;

  /// Seat that has to act now, or null (game over, waiting for a deal …).
  int? get seatToMove;

  /// One action of the computer on [seat] (update the game and send it).
  void botAct(int seat);

  Duration get botDelay => const Duration(milliseconds: 700);

  bool _botScheduled = false;

  /// Call after every change of the game.
  void scheduleBot() {
    final seat = seatToMove;
    if (seat == null || _botScheduled) return;
    if (!setup.isBot(seat) || !setup.controls(seat)) return;
    _botScheduled = true;
    Future<void>.delayed(BotSpeed.of(botDelay), () {
      _botScheduled = false;
      if (!mounted || seatToMove != seat) return;
      botAct(seat);
      scheduleBot();
    });
  }
}
