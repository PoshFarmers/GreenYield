import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/profile.dart';

class LocationResult {
  final GeoPoint point;
  final String displayText;

  const LocationResult({required this.point, required this.displayText});
}

/// Thrown for any failure to obtain a GPS fix — permission denial,
/// disabled services, or a timeout. `code` maps to a translation key
/// so the UI can show a localized message.
class LocationException implements Exception {
  final String code;
  const LocationException(this.code);

  @override
  String toString() => code;
}

/// Wraps device GPS + reverse geocoding into a single call. No map UI —
/// this just fetches the device's current fix and turns it into a
/// human-readable string for `profile.location_text`.
class LocationService {
  final _geocoding = Geocoding();

  Future<LocationResult> fetchCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('location_services_disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException('location_permission_denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException('location_permission_denied_forever');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    final point = GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    final displayText = await _reverseGeocode(point);
    return LocationResult(point: point, displayText: displayText);
  }

  Future<String> _reverseGeocode(GeoPoint point) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isEmpty) return _fallbackText(point);
      final p = placemarks.first;
      final parts = [
        p.locality,
        p.administrativeArea,
        p.country,
      ].where((s) => s != null && s.isNotEmpty).join(', ');
      return parts.isEmpty ? _fallbackText(point) : parts;
    } catch (_) {
      // Reverse geocoding can fail independently of the GPS fix (e.g. no
      // geocoding provider available on some desktop/web setups) — fall
      // back to raw coordinates rather than losing the fix entirely.
      return _fallbackText(point);
    }
  }

  String _fallbackText(GeoPoint point) =>
      '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
}
