import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../geo/geo_view.dart';

/// Places saved for "Wo bin ich?" rounds; they stay on this device.
class MyPlaces {
  MyPlaces._();

  static const _key = 'geoguess.places';
  static const max = 500;

  static Future<List<GeoView>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) ?GeoView.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<GeoView> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in places.take(max)) p.toJson()]),
    );
  }

  /// Adds [v] (the same picture only once); false if it was there already.
  static Future<bool> add(GeoView v) async {
    final list = await load();
    if (list.any((p) => p.source == v.source && p.id == v.id)) return false;
    await save([v, ...list]);
    return true;
  }

  static Future<void> remove(GeoView v) async {
    final list = await load();
    await save([
      for (final p in list)
        if (p.source != v.source || p.id != v.id) p,
    ]);
  }
}
