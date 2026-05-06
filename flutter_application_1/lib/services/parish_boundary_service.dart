import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import '../models/parish_boundary.dart';

class ParishBoundaryService {
  static final ParishBoundaryService _instance =
      ParishBoundaryService._internal();
  factory ParishBoundaryService() => _instance;
  ParishBoundaryService._internal();

  final List<ParishBoundary> _parishes = [];
  bool _isLoaded = false;

  Future<void> loadBoundaries() async {
    if (_isLoaded) return;

    try {
      // Load GeoJSON from assets
      final String geoJsonString = await rootBundle
          .loadString('assets/geojson/jamaica_parishes.geojson');
      final Map<String, dynamic> geoJson = json.decode(geoJsonString);

      // Parse features [citation:3]
      final features = geoJson['features'] as List;

      for (var feature in features) {
        final properties = feature['properties'];
        final geometry = feature['geometry'];

        String parishName = properties['PARISH_NAM'] ??
            properties['name'] ??
            properties['ADM1_EN'] ??
            'Unknown';

        // Parse polygons (handles both Polygon and MultiPolygon)
        final polygons = _parseGeometry(geometry);

        _parishes.add(ParishBoundary(
          name: _formatParishName(parishName),
          polygons: polygons,
        ));
      }

      _isLoaded = true;
      print('✅ Loaded ${_parishes.length} parish boundaries');
    } catch (e) {
      print('❌ Error loading parish boundaries: $e');
    }
  }

  List<List<LatLng>> _parseGeometry(Map<String, dynamic> geometry) {
    final List<List<LatLng>> polygons = [];
    final String type = geometry['type'];
    final coordinates = geometry['coordinates'];

    if (type == 'Polygon') {
      // Single polygon with possible holes
      for (var ring in coordinates) {
        polygons.add(_parseRing(ring));
      }
    } else if (type == 'MultiPolygon') {
      // Multiple polygons
      for (var polygon in coordinates) {
        for (var ring in polygon) {
          polygons.add(_parseRing(ring));
        }
      }
    }

    return polygons;
  }

  List<LatLng> _parseRing(List<dynamic> ring) {
    return ring.map<LatLng>((coord) {
      // GeoJSON format is [longitude, latitude]
      return LatLng(coord[1].toDouble(), coord[0].toDouble());
    }).toList();
  }

  String? getParishAtLocation(LatLng point) {
    for (var parish in _parishes) {
      if (parish.containsPoint(point)) {
        return parish.name;
      }
    }
    return null;
  }

  String _formatParishName(String raw) {
    // Clean up parish names
    return raw.replaceAll('Parish of ', '').replaceAll('Parish', '').trim();
  }

  bool get isLoaded => _isLoaded;
  List<ParishBoundary> get parishes => _parishes;
}
