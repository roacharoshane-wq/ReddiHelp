import 'package:geolocator/geolocator.dart';

class LocationHelper {
  static Future<Position> getCurrentLocation({
    bool enableHighAccuracy = true,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
          'Location services are disabled. Please enable location services.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
            'Location permissions are denied. Please grant location permission.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permissions are permanently denied. Please enable from settings.');
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy:
            enableHighAccuracy ? LocationAccuracy.high : LocationAccuracy.low,
        timeLimit: timeout,
      );
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  static Stream<Position> getPositionStream({
    bool enableHighAccuracy = true,
    int intervalMs = 5000,
    int distanceFilterM = 10,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: enableHighAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 30),
        distanceFilter: distanceFilterM,
      ),
    );
  }

  static double calculateDistance(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  // ... rest unchanged
}
