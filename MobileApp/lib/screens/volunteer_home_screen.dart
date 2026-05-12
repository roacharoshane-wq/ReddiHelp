import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../models/incident.dart';
import '../models/police_station.dart';
import '../services/api_service.dart';
import '../utils/location_helper.dart';
import '../providers/auth_provider.dart';
import '../services/tile_cache_service.dart';
import '../services/location_service.dart';
import 'chat_screen.dart';
import '../widgets/offline_banner.dart';
import '../widgets/redihelp_overlays.dart';

class VolunteerHomeScreen extends StatefulWidget {
  const VolunteerHomeScreen({super.key});

  @override
  State<VolunteerHomeScreen> createState() => _VolunteerHomeScreenState();
}

class _VolunteerHomeScreenState extends State<VolunteerHomeScreen> {
  final MapController _mapController = MapController();

  List<Marker> _markers = [];
  List<Incident> _allIncidents = [];
  List<Marker> _policeMarkers = [];
  bool _showPoliceStations = false;
  bool _loadingPolice = false;
  String? _volunteerId;
  Position? _currentPosition;
  bool _loading = true;
  bool _mapReady = false;
  String? _error;
  String? _volunteerName;

  final LatLng _defaultCenter = const LatLng(18.1096, -77.2975);

  int _selectedMapStyle = 0;
  final List<Map<String, String>> _mapStyles = [
    {
      'name': 'Street',
      'url': 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    },
    {
      'name': 'Dark',
      'url': 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    },
    {
      'name': 'Satellite',
      'url':
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    LocationTrackingService().startTracking(hasActiveTask: false);
  }

  @override
  void dispose() {
    LocationTrackingService().stopTracking();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Capture auth info before async gap to avoid unmounted context access.
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    _volunteerId = user?['id']?.toString();

    try {
      // Fetch location and incidents in parallel to reduce load time.
      final incidentFuture = ApiService.getIncidents();
      final Future<Position?> locationFuture =
          LocationHelper.getCurrentLocation(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 15),
      ).then<Position?>((value) => value).catchError((e) {
        print('⚠️ [VolunteerHome] Location fetch failed: $e');
        return null;
      });

      final allIncidents = await incidentFuture;
      print('📦 [VolunteerHome] Loaded ${allIncidents.length} incidents');

      _allIncidents = allIncidents;

      // Filter to show only active and in-progress
      final filtered = allIncidents
          .where((inc) => inc.status == 'active' || inc.status == 'in-progress')
          .toList();

      // Create markers for filtered incidents
      final markers = filtered.map((inc) {
        return Marker(
          point: LatLng(inc.lat, inc.lon),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _onIncidentTap(inc),
            child: Container(
              decoration: BoxDecoration(
                color: _severityColor(inc.severity),
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
                child: Icon(
                  _typeIcon(inc.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        );
      }).toList();

      _volunteerName = user?['username'] ?? 'Volunteer';

      if (!mounted) return;
      setState(() {
        _markers = markers;
        _loading = false;
      });

      final Position? pos = await locationFuture;
      if (!mounted) return;
      if (pos != null) {
        setState(() {
          _currentPosition = pos;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _mapReady && _currentPosition != null) {
            _mapController.move(
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              14,
            );
          }
        });
      }
    } catch (e) {
      print('❌ [VolunteerHome] Error loading data: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onIncidentTap(Incident incident) {
    _showIncidentOptions(incident);
  }

  void _showIncidentOptions(Incident incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _buildIncidentOptionsSheet(incident),
    );
  }

  Widget _buildIncidentOptionsSheet(Incident incident) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  incident.type[0].toUpperCase() + incident.type.substring(1),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.directions, color: Colors.teal),
                onPressed: () {
                  Navigator.pop(context);
                  _openDirections(incident);
                },
                tooltip: 'Get Directions',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Location: ${incident.areaId}'),
          Text('Severity: ${incident.severity}/5'),
          Text('Current Status: ${incident.status}'),
          if (incident.description.isNotEmpty)
            Text('Details: ${incident.description}'),
          const SizedBox(height: 16),
          const Text('Update Status:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statusButton('En Route', Colors.blue, incident, 'in-progress'),
              _statusButton('Resolved', Colors.green, incident, 'resolved'),
              _statusButton('Active', Colors.orange, incident, 'active'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      incidentId: incident.id,
                      incidentType: incident.type,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Open Chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: reddiPrimaryBlue,
                side: const BorderSide(color: reddiPrimaryBlue),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton(
      String label, Color color, Incident incident, String newStatus) {
    return ElevatedButton(
      onPressed: () async {
        Navigator.pop(context); // close bottom sheet
        await _updateIncidentStatus(incident.id, newStatus);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  // Future<void> _updateIncidentStatus(int id, String status) async {
  //   try {
  //     await ApiService.updateIncidentStatus(id, status);
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Status updated to $status'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //     }
  //     _loadData(); // refresh incidents
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Failed to update status: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  Future<void> _updateIncidentStatus(int id, String status) async {
    final success = await ApiService.updateIncidentStatus(id, status);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $status'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Update queued - will sync when online'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    // Always refresh — local cache was updated in either case.
    _loadData();
  }

  void _openDirections(Incident incident) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }

    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = '${incident.lat},${incident.lon}';
    final urlString = 'https://www.google.com/maps/dir/?api=1'
        '&origin=$origin&destination=$destination&travelmode=driving';

    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  List<Incident> get _assignedIncidents => _allIncidents
      .where((inc) => inc.assignedTo?.toString() == _volunteerId)
      .toList();

  void _showAssignedIncidents() {
    final assigned = _assignedIncidents;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) =>
            _buildAssignedIncidentsSheet(controller, assigned),
      ),
    );
  }

  void _showProfileOptions() {
    showProfileSkillsSheet(
      context,
      title: 'Volunteer Profile',
      primaryFieldLabel: 'Volunteer ID',
      primaryFieldKey: 'id',
      fallbackInitial: _volunteerName?[0].toUpperCase() ?? 'V',
      accentColor: reddiPrimaryBlue,
    );
  }

  Widget _buildAssignedIncidentsSheet(
      ScrollController controller, List<Incident> incidents) {
    final assignedIncidents = List<Incident>.from(incidents);
    if (_currentPosition != null) {
      assignedIncidents.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.lat,
          a.lon,
        );
        final distB = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.lat,
          b.lon,
        );
        return distA.compareTo(distB);
      });
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Assigned Incidents',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            '${assignedIncidents.length} assigned incident${assignedIncidents.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Divider(),
          Expanded(
            child: assignedIncidents.isEmpty
                ? Center(
                    child: Text(
                      'No incidents assigned to you yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: assignedIncidents.length,
                    itemBuilder: (ctx, index) {
                      final inc = assignedIncidents[index];
                      final distance = _currentPosition != null
                          ? Geolocator.distanceBetween(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                              inc.lat,
                              inc.lon,
                            )
                          : null;
                      return _buildIncidentCard(inc, distance);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPoliceStations() async {
    if (_loadingPolice) return;
    setState(() => _loadingPolice = true);
    try {
      final stations = await ApiService.getPoliceStations();
      if (!mounted) return;

      if (stations.isEmpty) {
        setState(() {
          _policeMarkers = [];
          _loadingPolice = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No police stations found. Check your connection.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final markers = stations.map((station) {
        return Marker(
          point: LatLng(station.lat, station.lon),
          width: 14,
          height: 14,
          child: GestureDetector(
            onTap: () => _showPoliceStationDetails(station),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        );
      }).toList();

      setState(() {
        _policeMarkers = markers;
        _loadingPolice = false;
      });
    } catch (e) {
      print('❌ [VolunteerHome] Error loading police stations: $e');
      if (!mounted) return;
      setState(() => _loadingPolice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load police stations.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPoliceStationDetails(PoliceStation station) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(station.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Parish: ${station.parish}'),
            if (station.address != null && station.address!.isNotEmpty)
              Text('Address: ${station.address}'),
            if (station.telephone != null && station.telephone!.isNotEmpty)
              Text('Telephone: ${station.telephone}'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openDirectionsForLocation(station.lat, station.lon);
                  },
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDirectionsForLocation(double lat, double lon) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }

    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = '$lat,$lon';
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 12),
                        Text('Error: $_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    // Offline banner at top
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: OfflineBanner(),
                    ),
                    FlutterMap(
                      key: const ValueKey('map'),
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPosition != null
                            ? LatLng(_currentPosition!.latitude,
                                _currentPosition!.longitude)
                            : _defaultCenter,
                        initialZoom: 12,
                        minZoom: 7,
                        cameraConstraint: CameraConstraint.containCenter(
                          bounds: LatLngBounds(
                            const LatLng(17.6, -78.5),
                            const LatLng(18.6, -76.1),
                          ),
                        ),
                        onMapReady: () {
                          setState(() {
                            _mapReady = true;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _mapStyles[_selectedMapStyle]['url']!,
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.example.disaster_response',
                          tileProvider: TileCacheService.getTileProvider(),
                        ),
                        MarkerLayer(markers: _markers),
                        if (_showPoliceStations && _policeMarkers.isNotEmpty)
                          MarkerLayer(markers: _policeMarkers),
                        if (_currentPosition != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                ),
                                width: 20,
                                height: 20,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: _showAssignedIncidents,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.notifications_none_rounded,
                                      size: 20,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                if (_assignedIncidents.isNotEmpty)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFE53935),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        _assignedIncidents.length > 99
                                            ? '99+'
                                            : '${_assignedIncidents.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => showPreparednessGuideSheet(context),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.menu_book_outlined,
                                    size: 20, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedMapStyle = (_selectedMapStyle + 1) %
                                      _mapStyles.length;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.layers, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                        _mapStyles[_selectedMapStyle]['name']!),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _showPoliceStations = !_showPoliceStations;
                                  if (_showPoliceStations &&
                                      _policeMarkers.isEmpty) {
                                    _loadPoliceStations();
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _showPoliceStations
                                      ? Colors.blue
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_police,
                                      size: 16,
                                      color: _showPoliceStations
                                          ? Colors.white
                                          : Colors.grey[700],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Police',
                                      style: TextStyle(
                                        color: _showPoliceStations
                                            ? Colors.white
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SafeArea(
                        child: GestureDetector(
                          onTap: _showProfileOptions,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white,
                            child: Text(
                              _volunteerName?[0].toUpperCase() ?? 'V',
                              style: TextStyle(
                                color: reddiPrimaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 24,
                      right: 16,
                      child: SafeArea(
                        child: FloatingActionButton(
                          heroTag: 'all_incidents',
                          onPressed: _showAllIncidents,
                          backgroundColor: reddiPrimaryBlue,
                          tooltip: 'All incidents',
                          child: const Icon(Icons.list_alt),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Color _severityColor(int severity) {
    if (severity >= 4) return Colors.red;
    if (severity >= 2) return Colors.orange;
    return Colors.green;
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'medical':
        return Icons.local_hospital;
      case 'fire':
        return Icons.local_fire_department;
      case 'flood':
        return Icons.water_drop;
      case 'trapped':
        return Icons.emergency;
      default:
        return Icons.warning;
    }
  }

  void _showAllIncidents() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _buildAllIncidentsSheet(controller),
      ),
    );
  }

  void showAllIncidents() {
    _showAllIncidents();
  }

  Widget _buildAllIncidentsSheet(ScrollController controller) {
    final statusOrder = ['active', 'in-progress', 'resolved'];
    final grouped = <String, List<Incident>>{};
    for (final status in statusOrder) {
      grouped[status] = [];
    }
    for (final inc in _allIncidents) {
      (grouped[inc.status] ??= []).add(inc);
    }

    for (final list in grouped.values) {
      if (_currentPosition != null) {
        list.sort((a, b) {
          final distA = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            a.lat,
            a.lon,
          );
          final distB = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            b.lat,
            b.lon,
          );
          return distA.compareTo(distB);
        });
      }
    }

    final widgets = <Widget>[];
    for (final status in statusOrder) {
      final list = grouped[status]!;
      if (list.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(status),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${list.length} incident${list.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      ));
      for (final inc in list) {
        final distance = _currentPosition != null
            ? Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                inc.lat,
                inc.lon,
              )
            : null;
        widgets.add(_buildIncidentCard(inc, distance));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'All Incidents',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            '${_allIncidents.length} total incidents',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Divider(),
          Expanded(
            child: _allIncidents.isEmpty
                ? Center(
                    child: Text('No incidents found',
                        style: TextStyle(color: Colors.grey[500])),
                  )
                : ListView(
                    controller: controller,
                    children: widgets,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(Incident inc, double? distance) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _onIncidentTap(inc);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _severityColor(inc.severity),
                    child: Icon(_typeIcon(inc.type),
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      inc.type[0].toUpperCase() + inc.type.substring(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  if (distance != null)
                    Text(
                      _formatDistance(distance),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Location: ${inc.areaId}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              Text(
                  'Severity: ${inc.severity}/5  •  ${_formatTimestamp(inc.timestamp)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              if (inc.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(inc.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
              const Divider(height: 16),
              _contactRow(
                icon: Icons.person,
                label: 'Victim',
                name: inc.victimName,
                phone: inc.victimPhone,
              ),
              const SizedBox(height: 6),
              _contactRow(
                icon: Icons.support_agent,
                label: 'Responder',
                name: inc.responderName,
                phone: inc.responderPhone,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required String label,
    String? name,
    String? phone,
  }) {
    final hasPhone = phone != null && phone.isNotEmpty;
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(
          child: Text(
            name != null && name.isNotEmpty
                ? '$name${hasPhone ? ' ($phone)' : ''}'
                : hasPhone
                    ? phone
                    : 'Unassigned',
            style: TextStyle(
              fontSize: 13,
              color: hasPhone ? Colors.black87 : Colors.grey[500],
            ),
          ),
        ),
        if (hasPhone)
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('tel:$phone')),
            child: const Icon(Icons.phone, color: Colors.teal, size: 20),
          ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.orange;
      case 'in-progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      final km = meters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
