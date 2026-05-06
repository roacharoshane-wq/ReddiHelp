class Stats {
  final int totalIncidents;
  final int activeIncidents;
  final int resolvedIncidents;
  final Map<String, int> byType;
  final Map<String, int> bySeverity;

  Stats({
    required this.totalIncidents,
    required this.activeIncidents,
    required this.resolvedIncidents,
    required this.byType,
    required this.bySeverity,
  });

  factory Stats.fromJson(Map<String, dynamic> json) {
    return Stats(
      totalIncidents: json['totalIncidents'],
      activeIncidents: json['activeIncidents'],
      resolvedIncidents: json['resolvedIncidents'],
      byType: Map<String, int>.from(json['byType']),
      bySeverity: Map<String, int>.from(json['bySeverity']),
    );
  }
}
