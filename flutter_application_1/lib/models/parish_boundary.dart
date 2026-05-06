import 'package:latlong2/latlong.dart';

class ParishBoundary {
  final String name;
  final List<List<LatLng>> polygons; // Supports polygons with holes

  ParishBoundary({
    required this.name,
    required this.polygons,
  });

  // Check if a point is inside this parish boundary
  bool containsPoint(LatLng point) {
    for (final polygon in polygons) {
      if (_isPointInPolygon(point, polygon)) {
        return true;
      }
    }
    return false;
  }

  // Ray-casting algorithm for point-in-polygon detection [citation:2]
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersectCount = 0;
    for (int i = 0; i < polygon.length - 1; i++) {
      if (_rayCastIntersect(point, polygon[i], polygon[i + 1])) {
        intersectCount++;
      }
    }

    // Odd number of intersections = point inside polygon
    return intersectCount % 2 == 1;
  }

  bool _rayCastIntersect(LatLng point, LatLng v1, LatLng v2) {
    // Check if the point is on the line segment
    if (_isPointOnSegment(point, v1, v2)) return true;

    // Ray casting algorithm
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
}
