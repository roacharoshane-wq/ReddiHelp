class PoliceStation {
  final String name;
  final String parish;
  final String? telephone;
  final String? address;
  final double lat;
  final double lon;

  PoliceStation({
    required this.name,
    required this.parish,
    this.telephone,
    this.address,
    required this.lat,
    required this.lon,
  });

  factory PoliceStation.fromGeoJson(Map<String, dynamic> feature) {
    final props = feature['properties'] ?? {};
    final geom = feature['geometry'];
    if (geom is! Map) {
      throw const FormatException('Missing geometry');
    }
    final coords = geom['coordinates'];
    if (coords is! List || coords.length < 2) {
      throw const FormatException('Invalid coordinates');
    }

    final lon = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lon == null || lat == null) {
      throw const FormatException('Invalid coordinate values');
    }
    return PoliceStation(
      name: props['Name'] ?? 'Unknown',
      parish: props['Parish'] ?? 'Unknown',
      telephone: props['Telephone'],
      address: props['Address_1'],
      lat: lat,
      lon: lon,
    );
  }

  factory PoliceStation.fromEsriJson(Map<String, dynamic> feature) {
    final attrs = feature['attributes'] ?? {};
    final geom = feature['geometry'];
    if (geom is! Map) {
      throw const FormatException('Missing geometry');
    }

    final lon = (geom['x'] as num?)?.toDouble();
    final lat = (geom['y'] as num?)?.toDouble();
    if (lon == null || lat == null) {
      throw const FormatException('Invalid coordinate values');
    }

    return PoliceStation(
      name: attrs['NAME'] ?? attrs['Name'] ?? 'Unknown',
      parish: attrs['PARISH'] ?? attrs['Parish'] ?? 'Unknown',
      telephone: attrs['TELEPHONE'] ?? attrs['Telephone'],
      address: attrs['Address'] ?? attrs['Address_1'],
      lat: lat,
      lon: lon,
    );
  }
}
