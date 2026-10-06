import 'package:flutter/material.dart';

import '../games/registry.dart';
import 'play_setup.dart';

/// Offline: how many players, and which seats the computer plays.
class SeatSetupScreen extends StatefulWidget {
  const SeatSetupScreen({super.key, required this.game});
  final GameInfo game;

  @override
  State<SeatSetupScreen> createState() => _SeatSetupScreenState();
}

class _SeatSetupScreenState extends State<SeatSetupScreen> {
  late int players = widget.game.playerCounts.contains(2)
      ? 2
      : widget.game.playerCounts.first;
  // Seat 0 is a person, the others start as computer players.
  final Set<int> bots = {1, 2, 3, 4, 5};

  int get humans => players - bots.where((b) => b < players).length;

  bool _canBePerson(int seat) {
    final max = widget.game.maxHumansOffline;
    return max == null || bots.contains(seat) == false || humans < max;
  }

  void _toggle(int seat) {
    setState(() {
      if (bots.contains(seat)) {
        if (_canBePerson(seat)) bots.remove(seat);
      } else if (humans > 1) {
        bots.add(seat);
      }
    });
  }

  void _start() {
    final setup = PlaySetup.local(
      players: players,
      bots: {
        for (final b in bots)
          if (b < players) b,
      },
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => widget.game.multiplayerBuilder!(setup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.game.title} – Spieler')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Wie viele Spieler?', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in widget.game.playerCounts)
                    ChoiceChip(
                      key: ValueKey('players$n'),
                      label: Text('$n'),
                      selected: players == n,
                      onSelected: (_) => setState(() => players = n),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Wer spielt?', style: theme.textTheme.titleMedium),
              Text(
                'Tippe einen Platz an, um zwischen Mensch und Computer zu '
                'wechseln. Menschen spielen abwechselnd auf diesem Gerät.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var seat = 0; seat < players; seat++)
                Card(
                  child: ListTile(
                    key: ValueKey('seat$seat'),
                    leading: Icon(
                      bots.contains(seat) ? Icons.smart_toy : Icons.person,
                    ),
                    title: Text('Platz ${seat + 1}'),
                    subtitle: Text(bots.contains(seat) ? 'Computer' : 'Mensch'),
                    trailing: Switch(
                      value: !bots.contains(seat),
                      onChanged: (_) => _toggle(seat),
                    ),
                    onTap: () => _toggle(seat),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('seatStart'),
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Spielen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
