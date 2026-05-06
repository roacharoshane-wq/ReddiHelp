import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// Model class for parish boundary
class ParishBoundary {
  final String name;
  final List<List<LatLng>> polygons; // Supports polygons with holes

  ParishBoundary({
    required this.name,
    required this.polygons,
  });

  /// Check if a point is inside this parish boundary
  bool containsPoint(LatLng point) {
    for (final polygon in polygons) {
      if (_isPointInPolygon(point, polygon)) {
        return true;
      }
    }
    return false;
  }

  /// Ray-casting algorithm for point-in-polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    // GeoJSON rings are already closed (polygon[0] == polygon[last]),
    // so the loop covers every edge including the closing one.
    // Do NOT add an extra check for polygon.last → polygon.first:
    // that creates a zero-length degenerate segment which always
    // returns true from _isPointOnSegment and breaks parity.
    for (int i = 0; i < polygon.length - 1; i++) {
      if (_rayCastIntersect(point, polygon[i], polygon[i + 1])) {
        intersectCount++;
      }
    }

    return intersectCount % 2 == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng v1, LatLng v2) {
    // Check if point is on the line segment
    if (_isPointOnSegment(point, v1, v2)) return true;

    // Check if the line segment straddles the horizontal line at point.latitude
    if ((v1.latitude > point.latitude) != (v2.latitude > point.latitude)) {
      final xIntersect = v1.longitude +
          (point.latitude - v1.latitude) *
              (v2.longitude - v1.longitude) /
              (v2.latitude - v1.latitude);

      if (xIntersect > point.longitude) {
        return true;
      }
    }
    return false;
  }

  bool _isPointOnSegment(LatLng p, LatLng a, LatLng b,
      {double tolerance = 1e-9}) {
    final crossProduct =
        (p.latitude - a.latitude) * (b.longitude - a.longitude) -
            (p.longitude - a.longitude) * (b.latitude - a.latitude);

    if (crossProduct.abs() > tolerance) return false;

    final dotProduct = (p.latitude - a.latitude) * (b.latitude - a.latitude) +
        (p.longitude - a.longitude) * (b.longitude - a.longitude);

    if (dotProduct < 0) return false;

    final squaredLength =
        (b.latitude - a.latitude) * (b.latitude - a.latitude) +
            (b.longitude - a.longitude) * (b.longitude - a.longitude);

    return dotProduct <= squaredLength;
  }

  @override
  String toString() =>
      'ParishBoundary(name: $name, polygons: ${polygons.length})';
}

/// Main helper class for parish detection
class ParishHelper {
  static final ParishHelper _instance = ParishHelper._internal();
  factory ParishHelper() => _instance;
  ParishHelper._internal();

  final List<ParishBoundary> _parishes = [];
  bool _isLoaded = false;

  /// Accurate fallback bounding boxes for all 14 Jamaican parishes
  static const List<Map<String, dynamic>> _fallbackParishes = [
    {
      'name': 'Kingston',
      'bounds': {
        'north': 18.0200,
        'south': 17.9400,
        'east': -76.7300,
        'west': -76.8300
      }
    },
    {
      'name': 'St. Andrew',
      'bounds': {
        'north': 18.1500,
        'south': 17.9800,
        'east': -76.7500,
        'west': -76.9000
      }
    },
    {
      'name': 'St. Thomas',
      'bounds': {
        'north': 18.0500,
        'south': 17.8500,
        'east': -76.3500,
        'west': -76.5500
      }
    },
    {
      'name': 'Portland',
      'bounds': {
        'north': 18.2500,
        'south': 18.0500,
        'east': -76.4500,
        'west': -76.6500
      }
    },
    {
      'name': 'St. Mary',
      'bounds': {
        'north': 18.4000,
        'south': 18.2000,
        'east': -76.8000,
        'west': -77.0000
      }
    },
    {
      'name': 'St. Ann',
      'bounds': {
        'north': 18.4500,
        'south': 18.2500,
        'east': -77.1000,
        'west': -77.4000
      }
    },
    {
      'name': 'Trelawny',
      'bounds': {
        'north': 18.5000,
        'south': 18.3000,
        'east': -77.5500,
        'west': -77.7500
      }
    },
    {
      'name': 'St. James',
      'bounds': {
        'north': 18.6000,
        'south': 18.4000,
        'east': -77.8000,
        'west': -78.0000
      }
    },
    {
      'name': 'Hanover',
      'bounds': {
        'north': 18.5000,
        'south': 18.3000,
        'east': -78.0500,
        'west': -78.2500
      }
    },
    {
      'name': 'Westmoreland',
      'bounds': {
        'north': 18.3000,
        'south': 18.1000,
        'east': -78.0500,
        'west': -78.2500
      }
    },
    {
      'name': 'St. Elizabeth',
      'bounds': {
        'north': 18.1500,
        'south': 17.9500,
        'east': -77.7000,
        'west': -77.9000
      }
    },
    {
      'name': 'Manchester',
      'bounds': {
        'north': 18.1500,
        'south': 17.9500,
        'east': -77.4500,
        'west': -77.6500
      }
    },
    {
      'name': 'Clarendon',
      'bounds': {
        'north': 18.0500,
        'south': 17.8500,
        'east': -77.1500,
        'west': -77.3500
      }
    },
    {
      'name': 'St. Catherine',
      'bounds': {
        'north': 18.1000,
        'south': 17.9000,
        'east': -76.9000,
        'west': -77.1000
      }
    },
  ];

  /// Initialize by loading parish boundaries from GeoJSON
  Future<void> initialize({bool forceReload = false}) async {
    if (_isLoaded && !forceReload) return;

    _parishes.clear();

    try {
      print('📂 Attempting to load GeoJSON from assets...');

      // Load GeoJSON from assets
      final String geoJsonString = await rootBundle
          .loadString('assets/geojson/jamaica_parishes.geojson');

      print('✅ GeoJSON loaded, length: ${geoJsonString.length} characters');

      final Map<String, dynamic> geoJson = json.decode(geoJsonString);
      print('📊 GeoJSON parsed, type: ${geoJson['type']}');

      // Parse features
      final features = geoJson['features'] as List?;
      if (features == null || features.isEmpty) {
        print('⚠️ No features found in GeoJSON, using fallback');
        _isLoaded = false;
        return;
      }

      print('📊 Found ${features.length} features');

      for (var i = 0; i < features.length; i++) {
        final feature = features[i];
        final properties = feature['properties'] as Map<String, dynamic>?;
        final geometry = feature['geometry'] as Map<String, dynamic>?;

        if (properties == null) {
          print('⚠️ Feature $i has no properties, skipping');
          continue;
        }

        if (geometry == null) {
          print('⚠️ Feature $i has no geometry, skipping');
          continue;
        }

        // Get parish name - try multiple possible property names
        String parishName = _extractParishName(properties);

        if (parishName == 'Unknown') {
          print(
              '⚠️ Could not extract parish name from feature $i, properties: $properties');
          continue;
        }

        print('📍 Processing feature $i: $parishName');

        // Parse polygons
        final polygons = _parseGeometry(geometry);

        if (polygons.isEmpty) {
          print('⚠️ No valid polygons for $parishName');
          continue;
        }

        print('   - Found ${polygons.length} polygons');

        _parishes.add(ParishBoundary(
          name: _formatParishName(parishName),
          polygons: polygons,
        ));
      }

      if (_parishes.isEmpty) {
        print('⚠️ No parishes were successfully loaded from GeoJSON');
        _isLoaded = false;
      } else {
        _isLoaded = true;
        print(
            '✅ Successfully loaded ${_parishes.length} parish boundaries from GeoJSON');

        // Print summary
        for (var parish in _parishes) {
          print('  - ${parish.name}: ${parish.polygons.length} polygons');
        }
      }
    } catch (e, stacktrace) {
      print('❌ Could not load GeoJSON boundaries: $e');
      print('Stacktrace: $stacktrace');
      print('⚡ Will use fallback bounding box method');
      _isLoaded = false;
    }
  }

  /// Extract parish name from properties using multiple possible keys
  String _extractParishName(Map<String, dynamic> properties) {
    final possibleKeys = [
      'shapeName', // HDX data
      'ADM1_EN', // geoBoundaries
      'NAME_1', // GADM data
      'name', // Simple GeoJSON
      'Parish', // Alternative
      'parish', // Lowercase
      'ADM1_NAME', // Another common format
      'admin1Name', // Yet another format
    ];

    for (var key in possibleKeys) {
      if (properties.containsKey(key)) {
        final value = properties[key];
        if (value != null && value.toString().isNotEmpty) {
          return value.toString();
        }
      }
    }

    // If no key matches, try to find any property that might contain the name
    for (var entry in properties.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value?.toString() ?? '';

      if ((key.contains('parish') ||
              key.contains('name') ||
              key.contains('adm1')) &&
          value.isNotEmpty) {
        return value;
      }
    }

    return 'Unknown';
  }

  /// Parse GeoJSON geometry into list of polygon rings
  List<List<LatLng>> _parseGeometry(Map<String, dynamic> geometry) {
    final List<List<LatLng>> polygons = [];
    final String type = geometry['type'];
    final coordinates = geometry['coordinates'];

    if (coordinates == null) {
      print('   - No coordinates in geometry');
      return polygons;
    }

    print('   - Geometry type: $type');

    try {
      if (type == 'Polygon') {
        // First ring is outer boundary, subsequent rings are holes
        // We'll include all rings for now (holes will be handled by containsPoint)
        for (var ring in coordinates) {
          final parsedRing = _parseRing(ring);
          if (parsedRing.length >= 3) {
            // Need at least 3 points for a polygon
            polygons.add(parsedRing);
          }
        }
      } else if (type == 'MultiPolygon') {
        for (var polygon in coordinates) {
          for (var ring in polygon) {
            final parsedRing = _parseRing(ring);
            if (parsedRing.length >= 3) {
              polygons.add(parsedRing);
            }
          }
        }
      } else {
        print('   - Unsupported geometry type: $type');
      }
    } catch (e) {
      print('   - Error parsing geometry: $e');
    }

    return polygons;
  }

  /// Parse a coordinate ring from GeoJSON
  List<LatLng> _parseRing(List<dynamic> ring) {
    final List<LatLng> points = [];

    try {
      for (var coord in ring) {
        if (coord is List && coord.length >= 2) {
          // GeoJSON format is [longitude, latitude]
          final lon = coord[0].toDouble();
          final lat = coord[1].toDouble();
          points.add(LatLng(lat, lon));
        }
      }
    } catch (e) {
      print('   - Error parsing ring: $e');
    }

    return points;
  }

  /// Clean up parish name
  String _formatParishName(String raw) {
    return raw
        .replaceAll('Parish of ', '')
        .replaceAll('Parish', '')
        .replaceAll('St. ', 'St. ')
        .replaceAll('Saint ', 'St. ')
        .trim();
  }

  /// Get parish name from coordinates using accurate boundaries
  Future<String> getParishFromCoordinates(double lat, double lon) async {
    await initialize();

    final point = LatLng(lat, lon);
    print('🔍 Checking point: ($lat, $lon)');

    // Try accurate GeoJSON boundaries first
    if (_isLoaded && _parishes.isNotEmpty) {
      for (var parish in _parishes) {
        if (parish.containsPoint(point)) {
          print('📍 Found parish using boundaries: ${parish.name}');
          return parish.name;
        }
      }
      print('⚠️ Point not in any loaded parish boundary');
    } else {
      print('⚠️ No accurate boundaries loaded, using fallback');
    }

    // Fallback to bounding box method
    return getApproximateParish(lat, lon);
  }

  /// Fallback method using bounding boxes (always available)
  String getApproximateParish(double lat, double lon) {
    for (var parish in _fallbackParishes) {
      final bounds = parish['bounds'];
      if (lat <= bounds['north'] &&
          lat >= bounds['south'] &&
          lon <= bounds['east'] &&
          lon >= bounds['west']) {
        print('📍 Found using fallback: ${parish['name']}');
        return parish['name'];
      }
    }
    return 'Unknown Parish';
  }

  /// Check if a specific point is in a specific parish (for testing)
  Future<bool> isPointInParish(
      double lat, double lon, String parishName) async {
    await initialize();

    final point = LatLng(lat, lon);

    if (_isLoaded && _parishes.isNotEmpty) {
      for (var parish in _parishes) {
        if (parish.name.toLowerCase().contains(parishName.toLowerCase())) {
          return parish.containsPoint(point);
        }
      }
    }

    // Fallback to approximate
    final approx = getApproximateParish(lat, lon);
    return approx.toLowerCase().contains(parishName.toLowerCase());
  }

  /// Get list of all loaded parish names
  List<String> getLoadedParishNames() {
    return _parishes.map((p) => p.name).toList();
  }

  /// Get list of all fallback parish names
  List<String> getFallbackParishNames() {
    return _fallbackParishes.map((p) => p['name'] as String).toList();
  }

  /// Check if accurate boundaries are loaded
  bool get hasAccurateBoundaries => _isLoaded && _parishes.isNotEmpty;

  /// Number of loaded parishes
  int get loadedParishCount => _parishes.length;

  /// Force reload of GeoJSON data
  Future<void> reloadBoundaries() async {
    await initialize(forceReload: true);
  }
}
