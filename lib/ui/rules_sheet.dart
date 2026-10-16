import 'package:flutter/material.dart';

import '../games/registry.dart';
import '../games/rules.dart';

/// The small "i" that opens the rules of [game].
class RulesButton extends StatelessWidget {
  const RulesButton({super.key, required this.game, this.color});
  final GameInfo game;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('rules-${game.id}'),
    tooltip: 'Regeln',
    visualDensity: VisualDensity.compact,
    icon: Icon(Icons.info_outline, color: color),
    onPressed: () => showRules(context, game),
  );
}

Future<void> showRules(BuildContext context, GameInfo game) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Icon(game.icon, color: game.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Regeln: ${game.title}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in (gameRules[game.id] ?? game.description).split(
              '\n',
            ))
              Padding(
                padding: EdgeInsets.only(
                  top: line.isEmpty ? 6 : 2,
                  left: line.startsWith('• ') ? 8 : 0,
                ),
                child: line.isEmpty ? null : Text(line),
              ),
          ],
        ),
      ),
    );
