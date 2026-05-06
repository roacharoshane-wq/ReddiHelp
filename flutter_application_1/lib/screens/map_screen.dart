import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../models/incident.dart';
import '../widgets/incident_marker.dart';
import '../widgets/incident_form.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<Incident> _incidents = [];
  List<Marker> _markers = [];
  List<CircleMarker> _circles = []; // <-- new list for circles
  LatLng? _selectedLocation;
  bool _autoLocatorEnabled = true;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadIncidents();
    _getCurrentLocation();
  }

  Future<void> _loadIncidents() async {
    try {
      final incidents = await ApiService.getIncidents();
      setState(() {
        _incidents = incidents;
        _updateMarkersAndCircles();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load incidents: $e')),
      );
    }
  }

  void _updateMarkersAndCircles() {
    _markers = _incidents
        .map((inc) => IncidentMarker(incident: inc).toMarker(context))
        .toList();

    // Build circles based on incident severity
    _circles = _incidents.map((inc) {
      // Base radius: 100 meters for severity 1, up to 500 meters for severity 5
      final radius = inc.severity * 100.0; // in meters
      return CircleMarker(
        point: LatLng(inc.lat, inc.lon),
        color: _getCircleColor(inc).withOpacity(0.2),
        borderColor: _getCircleColor(inc).withOpacity(0.5),
        borderStrokeWidth: 2,
        useRadiusInMeter: true,
        radius: radius,
      );
    }).toList();
  }

  Color _getCircleColor(Incident inc) {
    // Match the marker's severity color
    if (inc.severity >= 4) return Colors.red;
    if (inc.severity >= 2) return Colors.orange;
    return Colors.green;
  }

  Future<void> _getCurrentLocation() async {
    if (!_autoLocatorEnabled) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _currentPosition = position;
          _selectedLocation = null; // remove manual pin
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            14,
          );
        });
      }
    } catch (e) {
      print('Location error: $e');
    }
  }

  void _onMapDoubleTap(TapPosition tap, LatLng point) {
    setState(() {
      _autoLocatorEnabled = false;
      _selectedLocation = point;
    });
  }

  void _openReportForm(String incidentType) {
    print('📱 Opening form for incident type: $incidentType');

    if (_selectedLocation == null && _currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location by double-tapping the map'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => IncidentForm(
        initialLocation: _selectedLocation ??
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        incidentType: incidentType,
        onSubmit: (incident) async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );

          try {
            print('📤 Submitting incident...');
            await ApiService.postIncident(incident);

            if (context.mounted) {
              Navigator.pop(context); // Close loading dialog
              Navigator.pop(context); // Close form

              await _loadIncidents(); // Reload incidents

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Incident reported successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            print('❌ Submission error: $e');
            if (context.mounted) {
              Navigator.pop(context); // Close loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Failed to report: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(17.9712, -76.7936),
              initialZoom: 12,
              onTap: (tapPosition, point) {
                if (!_autoLocatorEnabled || _selectedLocation != null) {
                  setState(() {
                    _selectedLocation = point;
                  });
                }
              },
              onLongPress: _onMapDoubleTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              // Draw circles first so they appear behind markers
              CircleLayer(circles: _circles),
              MarkerLayer(markers: _markers),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      child: const Icon(Icons.location_pin,
                          color: Colors.red, size: 40),
                    ),
                  ],
                ),
              if (_currentPosition != null && _autoLocatorEnabled)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      child: const Icon(Icons.my_location_sharp,
                          color: Colors.blue, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          // FAB Menu
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'fab_main',
                  child: const Icon(Icons.add),
                  onPressed: () {
                    showMenu(
                      context: context,
                      position: const RelativeRect.fromLTRB(100, 100, 20, 20),
                      items: const [
                        PopupMenuItem(
                            value: 'medical', child: Text('🚑 Medical')),
                        PopupMenuItem(value: 'fire', child: Text('🔥 Fire')),
                        PopupMenuItem(value: 'flood', child: Text('💧 Flood')),
                        PopupMenuItem(
                            value: 'trapped', child: Text('🪨 Trapped')),
                      ],
                    ).then((value) {
                      if (value != null) _openReportForm(value);
                    });
                  },
                ),
              ],
            ),
          ),
          // Navigation bar
          Positioned(
            top: 40,
            left: 10,
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Data'),
                  onPressed: () => Navigator.pushNamed(context, '/incidents'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: const Text('Locate'),
                  onPressed: _getCurrentLocation,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.satellite),
                  label: const Text('Auto'),
                  onPressed: () {
                    setState(() {
                      _autoLocatorEnabled = true;
                      _selectedLocation = null;
                    });
                    _getCurrentLocation();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
