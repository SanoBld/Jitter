// ─────────────────────────────────────────────────────────────────────────────
// REQUIRED — add to pubspec.yaml:
//   dependencies:
//     geolocator: ^10.1.0
//
// REQUIRED — add to android/app/src/main/AndroidManifest.xml (inside <manifest>):
//   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
//   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
//
// REQUIRED — iOS: add to ios/Runner/Info.plist:
//   <key>NSLocationWhenInUseUsageDescription</key>
//   <string>Jitter shows your real city next to test results.</string>
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  // Get GPS coordinates from the device sensor.
  // Returns null if permission is denied or location is unavailable.
  static Future<({double lat, double lng})?> getGpsCoords() async {
    try {
      // Check if location services are enabled at all
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // Check / request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Low accuracy is enough to get the city name
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit:       const Duration(seconds: 12),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // Reverse-geocode a GPS coordinate to a "City, COUNTRY" string.
  // Uses OpenStreetMap Nominatim — free, no API key, no account required.
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&zoom=10&accept-language=en',
      );
      final resp = await http
          .get(uri, headers: {
            'User-Agent': 'JitterApp/1.0 (speed-test)',
            'Accept':     'application/json',
          })
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        // Try several levels of specificity, from most to least
        final city = addr['city']         as String?
            ?? addr['town']               as String?
            ?? addr['village']            as String?
            ?? addr['municipality']       as String?
            ?? addr['county']             as String?
            ?? '';
        final country =
            (addr['country_code'] as String? ?? '').toUpperCase();

        return [city, country].where((s) => s.isNotEmpty).join(', ');
      }
    } catch (_) {}
    return '';
  }

  // Full GPS flow: get coords then reverse-geocode.
  // Returns (gpsCity: "Lyon, FR", lat: 45.7, lng: 4.8) or empty on failure.
  static Future<({String city, double? lat, double? lng})> getGpsLocation() async {
    final coords = await getGpsCoords();
    if (coords == null) return (city: '', lat: null, lng: null);
    final city = await reverseGeocode(coords.lat, coords.lng);
    return (city: city, lat: coords.lat, lng: coords.lng);
  }

  // Check permission status without requesting it.
  static Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
             p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }
}