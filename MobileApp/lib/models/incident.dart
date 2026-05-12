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

  final int? peopleAffected; // number of people affected (SOS form)
  final String?
      referenceNumber; // generated incident reference (SOS confirmation)
  final int? submittedBy; // user id of the submitter
  final int?
      assignedTo; // volunteer/responder user id assigned to this incident
  final String? victimPhone;
  final String? victimName;
  final String? responderPhone;
  final String? responderName;

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
    this.peopleAffected,
    this.referenceNumber,
    this.submittedBy,
    this.assignedTo,
    this.victimPhone,
    this.victimName,
    this.responderPhone,
    this.responderName,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] ?? 0,
      type: json['type'] ?? 'unknown',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] ?? 1,
      description: json['description'] ?? '',
      disasterType: json['disasterType'] ?? json['disaster_type'] ?? 'other',
      areaId: json['areaId'] ?? json['area_id'] ?? 'unknown',
      status: json['status'] ?? 'active',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : (json['created_at'] != null
              ? DateTime.parse(json['created_at'].toString())
              : DateTime.now()),
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'].toString())
          : (json['updated_at'] != null
              ? DateTime.parse(json['updated_at'].toString())
              : DateTime.now()),
      peopleAffected: json['peopleAffected'] as int?,
      referenceNumber: json['referenceNumber'] as String?,
      submittedBy: json['submittedBy'] ?? json['submitted_by'],
      assignedTo: json['assignedTo'] ?? json['assigned_to'],
      victimPhone: json['victimPhone'] as String?,
      victimName: json['victimName'] as String?,
      responderPhone: json['responderPhone'] as String?,
      responderName: json['responderName'] as String?,
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
        if (peopleAffected != null) 'peopleAffected': peopleAffected,
        if (referenceNumber != null) 'referenceNumber': referenceNumber,
        if (submittedBy != null) 'submittedBy': submittedBy,
        if (assignedTo != null) 'assignedTo': assignedTo,
      };

  Incident copyWith({
    int? id,
    String? type,
    double? lat,
    double? lon,
    int? severity,
    String? description,
    String? disasterType,
    String? areaId,
    String? status,
    DateTime? timestamp,
    DateTime? lastUpdated,
    int? peopleAffected,
    String? referenceNumber,
    int? submittedBy,
    int? assignedTo,
    String? victimPhone,
    String? victimName,
    String? responderPhone,
    String? responderName,
  }) {
    return Incident(
      id: id ?? this.id,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      disasterType: disasterType ?? this.disasterType,
      areaId: areaId ?? this.areaId,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      peopleAffected: peopleAffected ?? this.peopleAffected,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      submittedBy: submittedBy ?? this.submittedBy,
      assignedTo: assignedTo ?? this.assignedTo,
      victimPhone: victimPhone ?? this.victimPhone,
      victimName: victimName ?? this.victimName,
      responderPhone: responderPhone ?? this.responderPhone,
      responderName: responderName ?? this.responderName,
    );
  }
}
