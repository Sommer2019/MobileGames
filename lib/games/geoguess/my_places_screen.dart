import 'package:flutter/material.dart';

import '../geo/geo_view.dart';
import '../geo/my_location.dart';
import '../geo/regions.dart';
import '../geo/street_view.dart';
import 'my_places.dart';

/// Collects places for "Wo bin ich?": walk anywhere (or jump to where you
/// are) and save the view as a riddle.
class MyPlacesScreen extends StatefulWidget {
  const MyPlacesScreen({
    super.key,
    required this.sources,
    this.controller,
    this.viewBuilder,
    this.locate = myLocation,
  });

  final List<GeoSource> sources;

  /// Replace the page, the street pictures and the location (tests).
  final StreetViewController? controller;
  final Widget Function()? viewBuilder;
  final Future<((double, double)?, String?)> Function() locate;

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  late final StreetViewController _view =
      widget.controller ?? StreetViewController();
  List<GeoView> _places = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    if (widget.controller == null) _view.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await MyPlaces.load();
    if (mounted) setState(() => _places = list);
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _here() async {
    setState(() => _busy = true);
    final (pos, error) = await widget.locate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (pos == null) {
      _say(error ?? 'Standort nicht verfügbar.');
      return;
    }
    _view.goTo(pos.$1, pos.$2);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final (view, error) = await _view.mark();
    if (!mounted) return;
    setState(() => _busy = false);
    if (view == null) {
      _say(error ?? 'Fehler');
      return;
    }
    final added = await MyPlaces.add(view);
    await _reload();
    if (!mounted) return;
    _say(added ? 'Ort gespeichert 📍' : 'Diesen Ort hast du schon.');
  }

  Future<void> _list() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => _places.isEmpty
            ? const Center(child: Text('Noch keine eigenen Orte.'))
            : ListView(
                controller: scroll,
                children: [
                  for (final p in _places)
                    ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(
                        countryByCode[p.country]?.name ?? 'Unbekanntes Land',
                      ),
                      subtitle: Text(
                        '${p.lat.toStringAsFixed(4)}, '
                        '${p.lng.toStringAsFixed(4)} · ${p.source.label}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Löschen',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await MyPlaces.remove(p);
                          await _reload();
                          setSheet(() {});
                        },
                      ),
                    ),
                ],
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eigene Orte'),
        actions: [
          TextButton.icon(
            key: const ValueKey('myPlacesList'),
            onPressed: _list,
            icon: const Icon(Icons.list),
            label: Text('${_places.length}'),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Such dir einen Ort – auf der Karte oder da, wo du gerade bist – '
              'und speichere die Ansicht. Als Host kannst du dann mit deinen '
              'Orten spielen.',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child:
                widget.viewBuilder?.call() ??
                StreetView(
                  controller: _view,
                  sources: widget.sources,
                  mode: StreetViewMode.hunt,
                ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('myPlacesHere'),
                  onPressed: _busy ? null : _here,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Mein Standort'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('myPlacesSave'),
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Ort speichern'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
