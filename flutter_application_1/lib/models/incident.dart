class Incident {
  final int id;
  final String type;
  final double lat;
  final double lon;
  final int severity;
  final String description;
  final String disasterType;
  final String areaId;
  final String status;
  final DateTime timestamp;
  final DateTime lastUpdated;

  Incident({
    required this.id,
    required this.type,
    required this.lat,
    required this.lon,
    required this.severity,
    required this.description,
    required this.disasterType,
    required this.areaId,
    required this.status,
    required this.timestamp,
    required this.lastUpdated,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] ?? 0, // fallback (id should never be null)
      type: json['type'] ?? 'unknown',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] ?? 1, // default severity
      description: json['description'] ?? '',
      disasterType: json['disasterType'] ?? 'other',
      areaId: json['areaId'] ?? 'unknown',
      status: json['status'] ?? 'active',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
    );
  }
  Map<String, dynamic> toJson() => {
        'type': type,
        'lat': lat,
        'lon': lon,
        'severity': severity,
        'description': description,
        'disasterType': disasterType,
        'areaId': areaId,
      };
}
