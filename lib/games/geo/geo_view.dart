/// Where the street pictures come from.
enum GeoSource {
  google('Google Street View'),
  mapillary('Mapillary'),
  panoramax('Panoramax');

  const GeoSource(this.label);
  final String label;

  /// Panoramax is open to everybody; the others need a key.
  bool get needsKey => this != panoramax;

  /// Whether these sources can be played together: Google only alone
  /// (its map and coverage cannot be mixed with the free ones), the free
  /// ones in any combination.
  static bool validMix(List<GeoSource> s) =>
      s.isNotEmpty &&
      s.toSet().length == s.length &&
      (!s.contains(google) || s.length == 1);

  /// Sources from a message, null if invalid.
  static List<GeoSource>? parseMix(Object? j) {
    if (j is! List || j.length > values.length) return null;
    final list = <GeoSource>[];
    for (final x in j) {
      final s = values.asNameMap()[x];
      if (s == null) return null;
      list.add(s);
    }
    return validMix(list) ? list : null;
  }
}

/// A marked spot in a street panorama: the picture and the direction the
/// player looked in when marking it.
class GeoView {
  const GeoView({
    required this.source,
    required this.id,
    required this.lat,
    required this.lng,
    this.heading = 0,
    this.pitch = 0,
    this.zoom = 1,
    this.country = '',
  });

  final GeoSource source;

  /// Google panorama id, Mapillary image id or Panoramax picture id.
  final String id;
  final double lat;
  final double lng;
  final double heading;
  final double pitch;
  final double zoom;

  /// ISO country code (lower case), '' if unknown.
  final String country;

  static GeoView? fromJson(Object? j) {
    if (j is! Map) return null;
    final src = GeoSource.values.asNameMap()[j['src']];
    final id = j['id'];
    num? n(String k) => j[k] is num ? j[k] as num : null;
    final lat = n('lat'), lng = n('lng');
    if (src == null || id is! String || id.isEmpty || id.length > 200) {
      return null;
    }
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    final cc = j['cc'];
    return GeoView(
      source: src,
      id: id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      heading: (n('h') ?? 0).toDouble(),
      pitch: (n('p') ?? 0).toDouble(),
      zoom: (n('z') ?? 1).toDouble(),
      country: cc is String && cc.length <= 3 ? cc.toLowerCase() : '',
    );
  }

  Map<String, dynamic> toJson() => {
    'src': source.name,
    'id': id,
    'lat': lat,
    'lng': lng,
    'h': heading,
    'p': pitch,
    'z': zoom,
    if (country.isNotEmpty) 'cc': country,
  };
}
