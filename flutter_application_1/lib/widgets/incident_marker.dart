//import 'dart:math'; // <-- added for π
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/incident.dart';

class IncidentMarker extends StatelessWidget {
  final Incident incident;

  const IncidentMarker({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    return Container(); // This widget is not used directly; we use toMarker()
  }

  Marker toMarker(BuildContext context) {
    return Marker(
      point: LatLng(incident.lat, incident.lon),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          _showPopup(context);
        },
        child: Container(
          decoration: BoxDecoration(
            color: _getSeverityColor(),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(_getIconData(), color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  void _showPopup(BuildContext context) {
    // Calculate estimated affected area based on severity
    final radiusMeters = incident.severity * 100.0; // 100–500 m
    final areaSqKm = (pi * radiusMeters * radiusMeters) / 1e6; // convert to km²

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${incident.type.toUpperCase()} EMERGENCY'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Severity: ${incident.severity}/5'),
              // New line: estimated affected area
              Text(
                'Estimated affected area: ${radiusMeters.toStringAsFixed(0)} m radius '
                '(${areaSqKm.toStringAsFixed(1)} km²)',
              ),
              if (incident.description.isNotEmpty)
                Text('Details: ${incident.description}'),
              Text('Disaster: ${incident.disasterType}'),
              Text('Area: ${incident.areaId}'),
              Text('Status: ${incident.status}'),
              Text('Reported: ${_formatDate(incident.timestamp)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.toLocal()}'.split('.')[0]; // remove milliseconds
  }

  IconData _getIconData() {
    switch (incident.type) {
      case 'medical':
        return Icons.local_hospital;
      case 'fire':
        return Icons.local_fire_department;
      case 'flood':
        return Icons.water_drop;
      case 'trapped':
        return Icons.emergency;
      case 'other':
      default:
        return Icons.warning;
    }
  }

  Color _getSeverityColor() {
    if (incident.severity >= 4) return Colors.red;
    if (incident.severity >= 2) return Colors.orange;
    return Colors.green;
  }
}
