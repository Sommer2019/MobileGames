import 'package:flutter/material.dart';

import 'geo_view.dart';

/// Chooses where the pictures come from: Google alone, or any mix of the
/// free sources.
class SourcePicker extends StatelessWidget {
  const SourcePicker({
    super.key,
    required this.available,
    required this.selected,
    this.onChanged,
  });

  final List<GeoSource> available;
  final List<GeoSource> selected;

  /// Null: only shows the choice (not the host).
  final ValueChanged<List<GeoSource>>? onChanged;

  static String label(List<GeoSource> s) => s.map((x) => x.label).join(' + ');

  void _tap(GeoSource s) {
    final List<GeoSource> next;
    if (s == GeoSource.google) {
      next = [GeoSource.google];
    } else {
      final free = selected.where((x) => x != GeoSource.google).toList();
      if (free.contains(s)) {
        free.remove(s);
      } else {
        free.add(s);
      }
      next = [
        for (final x in GeoSource.values)
          if (free.contains(x)) x,
      ];
    }
    if (next.isNotEmpty) onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return ListTile(
      leading: const Icon(Icons.public),
      title: Text('Bilder: ${label(selected)}'),
      subtitle: change == null || available.length < 2
          ? null
          : Wrap(
              spacing: 8,
              children: [
                for (final s in available)
                  FilterChip(
                    key: ValueKey('source-${s.name}'),
                    label: Text(s.label),
                    selected: selected.contains(s),
                    onSelected: (_) => _tap(s),
                  ),
              ],
            ),
    );
  }
}
