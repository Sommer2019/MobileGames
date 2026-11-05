import 'package:geolocator/geolocator.dart';

/// Where this device is: (lat, lng), or (null, why not).
Future<((double, double)?, String?)> myLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (null, 'Die Ortung ist ausgeschaltet.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return (null, 'Ohne Erlaubnis kein Standort.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return ((pos.latitude, pos.longitude), null);
  } catch (e) {
    return (null, 'Standort nicht verfügbar.');
  }
}
