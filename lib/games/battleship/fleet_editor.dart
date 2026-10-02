import 'dart:math';

import 'package:flutter/material.dart';

import 'battleship_logic.dart';

/// Sizes still missing from [fleet] (as a multiset of [fleetSizes]).
List<int> missingShips(FleetBoard fleet) {
  final left = [...fleetSizes];
  for (final s in fleet.ships) {
    left.remove(s.cells.length);
  }
  return left;
}

bool fleetComplete(FleetBoard fleet) => missingShips(fleet).isEmpty;

/// Lets the player place the fleet by hand: pick a ship, choose the
/// direction, tap the start cell. Tapping a placed ship picks it up again.
class FleetEditor extends StatefulWidget {
  const FleetEditor({super.key, required this.fleet, required this.onChanged});

  final FleetBoard fleet;
  final void Function(FleetBoard fleet) onChanged;

  @override
  State<FleetEditor> createState() => _FleetEditorState();
}

class _FleetEditorState extends State<FleetEditor> {
  bool horizontal = true;
  int? selected;
  (int, int)? hover;

  FleetBoard get fleet => widget.fleet;

  int? get _size {
    final missing = missingShips(fleet);
    if (missing.isEmpty) return null;
    final s = selected;
    return s != null && missing.contains(s) ? s : missing.first;
  }

  void _tapCell(int x, int y) {
    final ship = fleet.shipAt(x, y);
    if (ship != null) {
      // Pick the ship up again.
      fleet.ships.remove(ship);
      setState(() => selected = ship.cells.length);
      widget.onChanged(fleet);
      return;
    }
    final size = _size;
    if (size == null) return;
    if (fleet.place(x, y, size, horizontal)) {
      setState(() => selected = null);
      widget.onChanged(fleet);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Passt dort nicht – Schiffe dürfen sich nicht berühren.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Set<(int, int)> get _preview {
    final h = hover, size = _size;
    if (h == null || size == null || fleet.shipAt(h.$1, h.$2) != null) {
      return const {};
    }
    return FleetBoard.cellsFor(h.$1, h.$2, size, horizontal).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final missing = missingShips(fleet);
    final size = _size;
    final preview = _preview;
    final previewOk = preview.isNotEmpty && fleet.canPlace(preview.toList());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (missing.isEmpty)
                const Chip(
                  avatar: Icon(Icons.check_circle, color: Colors.green),
                  label: Text('Flotte vollständig'),
                )
              else
                for (final (i, s) in missing.indexed)
                  ChoiceChip(
                    key: ValueKey('ship-$i-$s'),
                    label: Text('${'■' * s}  $s'),
                    selected: s == size && missing.indexOf(s) == i,
                    onSelected: (_) => setState(() => selected = s),
                  ),
              IconButton.filledTonal(
                key: const ValueKey('rotateShip'),
                tooltip: 'Drehen',
                onPressed: () => setState(() => horizontal = !horizontal),
                icon: Icon(horizontal ? Icons.swap_horiz : Icons.swap_vert),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(2),
                color: const Color(0xFF0D47A1),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cell = min(c.maxWidth, c.maxHeight) / boardSize;
                    return MouseRegion(
                      onExit: (_) => setState(() => hover = null),
                      child: Column(
                        children: [
                          for (var y = 0; y < boardSize; y++)
                            Row(
                              children: [
                                for (var x = 0; x < boardSize; x++)
                                  GestureDetector(
                                    key: ValueKey('place$x-$y'),
                                    onTap: () => _tapCell(x, y),
                                    child: MouseRegion(
                                      onEnter: (_) =>
                                          setState(() => hover = (x, y)),
                                      child: Container(
                                        width: cell,
                                        height: cell,
                                        margin: EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: fleet.shipAt(x, y) != null
                                              ? const Color(0xFF90A4AE)
                                              : preview.contains((x, y))
                                              ? (previewOk
                                                    ? Colors.green.shade300
                                                    : Colors.red.shade300)
                                              : const Color(0xFF1976D2),
                                          border: Border.all(
                                            color: const Color(0xFF0D47A1),
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Text(
          missing.isEmpty
              ? 'Tippe ein Schiff an, um es wieder aufzunehmen.'
              : 'Feld antippen, um das ${size}er-Schiff '
                    '${horizontal ? 'waagerecht' : 'senkrecht'} zu setzen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () {
                fleet.ships.clear();
                widget.onChanged(fleet);
                setState(() {});
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Leeren'),
            ),
            TextButton.icon(
              key: const ValueKey('randomFleet'),
              onPressed: () => widget.onChanged(FleetBoard.random()),
              icon: const Icon(Icons.shuffle),
              label: const Text('Zufällig'),
            ),
          ],
        ),
      ],
    );
  }
}
