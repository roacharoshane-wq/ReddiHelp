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
import '../utils/parish_helper.dart';
import '../providers/auth_provider.dart';
import '../services/location_service.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/redihelp_overlays.dart';
import 'chat_screen.dart';

class ResponderHomeScreen extends StatefulWidget {
  const ResponderHomeScreen({super.key});

  @override
  State<ResponderHomeScreen> createState() => _ResponderHomeScreenState();
}

class _ResponderHomeScreenState extends State<ResponderHomeScreen> {
  final MapController _mapController = MapController();

  List<Incident> _allIncidents = [];
  List<Marker> _incidentMarkers = [];

  List<Marker> _policeMarkers = [];
  bool _showPoliceStations = false;
  bool _loadingPolice = false;

  Position? _currentPosition;
  bool _loading = true;
  bool _mapReady = false;
  String? _error;
  String? _responderName;
  String? _currentParish;
  List<Incident> _nearbyActiveIncidents = [];

  final LatLng _defaultCenter = const LatLng(18.1096, -77.2975);

  bool get _isCoordinator {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.userRole == 'coordinator' || auth.userRole == 'admin';
  }

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

    try {
      // Fetch location and incidents in parallel to reduce load time.
      final results = await Future.wait([
        LocationHelper.getCurrentLocation(
          enableHighAccuracy: true,
          timeout: const Duration(seconds: 15),
        ),
        ApiService.getIncidents(),
      ]);

      final pos = results[0] as Position;
      final allIncidents = results[1] as List<Incident>;
      print('📦 [ResponderHome] Loaded ${allIncidents.length} incidents');

      final filtered = allIncidents
          .where((inc) => inc.status == 'active' || inc.status == 'in-progress')
          .toList();

      final incidentMarkers = filtered.map((inc) {
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

      final parish = await ParishHelper()
          .getParishFromCoordinates(pos.latitude, pos.longitude);
      final nearbyActive = _filterNearbyActiveIncidents(filtered, pos, parish);

      _responderName = user?['username'] ?? 'Responder';

      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _allIncidents = allIncidents;
        _incidentMarkers = incidentMarkers;
        _currentParish = parish;
        _nearbyActiveIncidents = nearbyActive;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapReady && _currentPosition != null) {
          _mapController.move(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            14,
          );
        }
      });
    } catch (e) {
      print('❌ [ResponderHome] Error loading data: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
      print('❌ Error loading police stations: $e');
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

  void _openDirectionsForLocation(double lat, double lon) {
    if (_currentPosition == null) return;
    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = '$lat,$lon';
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _onIncidentTap(Incident incident) {
    _showIncidentOptions(incident);
  }

  void _showIncidentOptions(Incident incident) {
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
            _buildIncidentDetailSheet(incident, controller),
      ),
    );
  }

  Widget _buildIncidentDetailSheet(
      Incident incident, ScrollController controller) {
    final distance = _currentPosition != null
        ? Geolocator.distanceBetween(_currentPosition!.latitude,
            _currentPosition!.longitude, incident.lat, incident.lon)
        : null;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(20),
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Header: type icon, title, status badge
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _severityColor(incident.severity),
              child:
                  Icon(_typeIcon(incident.type), color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incident.type[0].toUpperCase() + incident.type.substring(1),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (incident.referenceNumber != null &&
                      incident.referenceNumber!.isNotEmpty)
                    Text(
                      'Ref: ${incident.referenceNumber}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(incident.status),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                incident.status.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Quick actions row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openDirections(incident);
                },
                icon: const Icon(Icons.directions, size: 18),
                label: Text(
                  distance != null
                      ? 'Directions (${_formatDistance(distance)})'
                      : 'Directions',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (incident.victimPhone != null &&
                incident.victimPhone!.isNotEmpty) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${incident.victimPhone}')),
                icon: const Icon(Icons.phone, size: 18),
                label: const Text('Call Victim'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  side: BorderSide(color: Colors.red[700]!),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
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
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Open Chat'),
            style: OutlinedButton.styleFrom(
              foregroundColor: reddiPrimaryBlue,
              side: const BorderSide(color: reddiPrimaryBlue),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Incident details card
        _detailCard('Incident Details', [
          _detailRow(Icons.category, 'Type',
              incident.type[0].toUpperCase() + incident.type.substring(1)),
          _detailRow(
              Icons.storm,
              'Disaster Type',
              incident.disasterType[0].toUpperCase() +
                  incident.disasterType.substring(1)),
          _detailRow(
              Icons.warning_amber, 'Severity', '${incident.severity} / 5',
              valueColor: _severityColor(incident.severity)),
          _detailRow(Icons.location_on, 'Parish', incident.areaId),
          _detailRow(Icons.my_location, 'Coordinates',
              '${incident.lat.toStringAsFixed(5)}, ${incident.lon.toStringAsFixed(5)}'),
          if (distance != null)
            _detailRow(Icons.straighten, 'Distance', _formatDistance(distance)),
          if (incident.peopleAffected != null)
            _detailRow(
                Icons.people, 'People Affected', '${incident.peopleAffected}'),
        ]),
        const SizedBox(height: 12),

        // Description card
        if (incident.description.isNotEmpty)
          _detailCard('Description', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(incident.description,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ]),
        if (incident.description.isNotEmpty) const SizedBox(height: 12),

        // Contacts card
        _detailCard('Contacts', [
          _contactDetailRow(
            Icons.person,
            'Victim',
            incident.victimName,
            incident.victimPhone,
          ),
          const Divider(height: 16),
          _contactDetailRow(
            Icons.support_agent,
            'Responder',
            incident.responderName,
            incident.responderPhone,
          ),
        ]),
        const SizedBox(height: 12),

        // Timestamps card
        _detailCard('Timeline', [
          _detailRow(Icons.access_time, 'Reported',
              _formatFullTimestamp(incident.timestamp)),
          _detailRow(Icons.update, 'Last Updated',
              _formatFullTimestamp(incident.lastUpdated)),
          _detailRow(
              Icons.timelapse, 'Age', _formatTimestamp(incident.timestamp)),
        ]),
        const SizedBox(height: 12),

        // IDs card
        _detailCard('Identifiers', [
          _detailRow(Icons.tag, 'Incident ID', '#${incident.id}'),
          if (incident.referenceNumber != null &&
              incident.referenceNumber!.isNotEmpty)
            _detailRow(
                Icons.confirmation_num, 'Reference', incident.referenceNumber!),
          if (incident.submittedBy != null)
            _detailRow(Icons.person_outline, 'Submitted By',
                'User #${incident.submittedBy}'),
          if (incident.assignedTo != null)
            _detailRow(Icons.assignment_ind, 'Assigned To',
                'User #${incident.assignedTo}'),
        ]),
        const SizedBox(height: 20),

        // Status update section
        const Text('Update Status',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child:
                    _statusChip('Active', Colors.orange, incident, 'active')),
            const SizedBox(width: 8),
            Expanded(
                child: _statusChip(
                    'En Route', Colors.blue, incident, 'in-progress')),
            const SizedBox(width: 8),
            Expanded(
                child: _statusChip(
                    'Resolved', Colors.green, incident, 'resolved')),
          ],
        ),

        // Coordinator: assign button
        if (_isCoordinator) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAssignDialog(incident);
              },
              icon: Icon(
                incident.assignedTo != null
                    ? Icons.swap_horiz
                    : Icons.person_add,
                size: 18,
              ),
              label: Text(incident.assignedTo != null
                  ? 'Reassign Responder'
                  : 'Assign Responder'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: const BorderSide(color: Colors.indigo),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _detailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _contactDetailRow(
      IconData icon, String label, String? name, String? phone) {
    final hasName = name != null && name.isNotEmpty;
    final hasPhone = phone != null && phone.isNotEmpty;
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500)),
              Text(
                hasName ? name : 'Unassigned',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hasName ? Colors.black87 : Colors.grey[400]),
              ),
              if (hasPhone)
                Text(phone,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
        if (hasPhone)
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.teal),
            onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            tooltip: 'Call $label',
          ),
      ],
    );
  }

  Widget _statusChip(
      String label, Color color, Incident incident, String newStatus) {
    final isActive = incident.status == newStatus;
    return GestureDetector(
      onTap: isActive
          ? null
          : () async {
              Navigator.pop(context);
              await _updateIncidentStatus(incident.id, newStatus);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _updateIncidentStatus(int id, String status) async {
    final success = await ApiService.updateIncidentStatus(id, status);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              success ? 'Status updated to $status' : 'Update queued for sync'),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
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
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
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
    // Group by status, ordered: active → in-progress → resolved
    final statusOrder = ['active', 'in-progress', 'resolved'];
    final grouped = <String, List<Incident>>{};
    for (final s in statusOrder) {
      grouped[s] = [];
    }
    for (final inc in _allIncidents) {
      (grouped[inc.status] ??= []).add(inc);
    }

    // Sort each group by distance from current position (nearest first)
    for (final list in grouped.values) {
      if (_currentPosition != null) {
        list.sort((a, b) {
          final distA = Geolocator.distanceBetween(_currentPosition!.latitude,
              _currentPosition!.longitude, a.lat, a.lon);
          final distB = Geolocator.distanceBetween(_currentPosition!.latitude,
              _currentPosition!.longitude, b.lat, b.lon);
          return distA.compareTo(distB);
        });
      }
    }

    // Build flat widget list with section headers
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
            ? Geolocator.distanceBetween(_currentPosition!.latitude,
                _currentPosition!.longitude, inc.lat, inc.lon)
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
              // Coordinator: assign/reassign button
              if (_isCoordinator) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showAssignDialog(inc),
                    icon: Icon(
                      inc.assignedTo != null
                          ? Icons.swap_horiz
                          : Icons.person_add,
                      size: 18,
                    ),
                    label: Text(inc.assignedTo != null
                        ? 'Reassign Responder'
                        : 'Assign Responder'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
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
    final hasContact = phone != null && phone.isNotEmpty;
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Expanded(
          child: Text(
            name != null && name.isNotEmpty
                ? '$name${hasContact ? ' ($phone)' : ''}'
                : hasContact
                    ? phone
                    : 'Unassigned',
            style: TextStyle(
              fontSize: 13,
              color: hasContact ? Colors.black87 : Colors.grey[500],
            ),
          ),
        ),
        if (hasContact)
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

  Future<void> _showAssignDialog(Incident incident) async {
    final volunteers = await ApiService.getVolunteers();
    if (!mounted) return;

    if (volunteers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No volunteers found'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, controller) => Container(
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
              Text(
                incident.assignedTo != null
                    ? 'Reassign Incident #${incident.id}'
                    : 'Assign Incident #${incident.id}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${incident.type[0].toUpperCase()}${incident.type.substring(1)} — ${incident.areaId}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: volunteers.length,
                  itemBuilder: (_, i) {
                    final v = volunteers[i];
                    final vId = v['id'] as int;
                    final isCurrentAssignee = incident.assignedTo == vId;
                    final availability =
                        v['availability'] as String? ?? 'available';
                    final skills = v['skills'] is List
                        ? (v['skills'] as List).join(', ')
                        : '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isCurrentAssignee
                            ? const BorderSide(color: Colors.indigo, width: 2)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrentAssignee
                              ? Colors.indigo
                              : availability == 'available'
                                  ? Colors.green
                                  : Colors.orange,
                          child: Text(
                            (v['username'] as String? ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                v['username'] as String? ?? 'User #$vId',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isCurrentAssignee)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.indigo,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Current',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${v['role'] ?? 'volunteer'} • $availability',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            if (skills.isNotEmpty)
                              Text('Skills: $skills',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                            if (v['phone'] != null)
                              Text('${v['phone']}',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                          ],
                        ),
                        trailing: isCurrentAssignee
                            ? const Icon(Icons.check_circle,
                                color: Colors.indigo)
                            : const Icon(Icons.arrow_forward_ios,
                                size: 16, color: Colors.grey),
                        onTap: isCurrentAssignee
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final success = await ApiService.assignIncident(
                                    incident.id, vId);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(success
                                          ? 'Assigned to ${v['username'] ?? 'User #$vId'}'
                                          : 'Assignment failed'),
                                      backgroundColor:
                                          success ? Colors.green : Colors.red,
                                    ),
                                  );
                                  if (success) _loadData();
                                }
                              },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNearbyIncidents() {
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
        builder: (_, controller) => _buildNearbyIncidentsSheet(controller),
      ),
    );
  }

  Widget _buildNearbyIncidentsSheet(ScrollController controller) {
    final incidents = List<Incident>.from(_nearbyActiveIncidents);

    if (_currentPosition != null) {
      incidents.sort((a, b) {
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

    final parishLabel =
        _currentParish ?? _closestIncidentParish(incidents, _currentPosition);

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
            'Nearby Incidents',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (parishLabel != null &&
              parishLabel.isNotEmpty &&
              !_isUnknownParish(parishLabel))
            Text(
              'Parish: $parishLabel',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          Text(
            '${incidents.length} active incident${incidents.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Divider(),
          Expanded(
            child: incidents.isEmpty
                ? Center(
                    child: Text(
                      'No nearby active incidents',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: incidents.length,
                    itemBuilder: (ctx, i) {
                      final inc = incidents[i];
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

  String _normalizeParishName(String value) {
    return value
        .toLowerCase()
        .replaceAll('parish of', '')
        .replaceAll('parish', '')
        .replaceAll('saint', 'st')
        .replaceAll('.', '')
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isUnknownParish(String value) {
    final normalized = _normalizeParishName(value);
    return normalized.isEmpty || normalized == 'unknown';
  }

  String? _closestIncidentParish(List<Incident> incidents, Position? position) {
    if (position == null || incidents.isEmpty) return null;
    double? bestDistance;
    String? bestParish;

    for (final inc in incidents) {
      if (_normalizeParishName(inc.areaId).isEmpty) continue;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        inc.lat,
        inc.lon,
      );
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestParish = inc.areaId;
      }
    }

    return bestParish;
  }

  List<Incident> _filterNearbyActiveIncidents(
    List<Incident> activeIncidents,
    Position? position,
    String? parish,
  ) {
    if (activeIncidents.isEmpty) return [];

    String? targetParish = parish;
    if (targetParish == null || _isUnknownParish(targetParish)) {
      targetParish = _closestIncidentParish(activeIncidents, position);
    }
    if (targetParish == null || targetParish.trim().isEmpty) {
      return [];
    }

    final normalizedTarget = _normalizeParishName(targetParish);
    return activeIncidents
        .where((inc) => _normalizeParishName(inc.areaId) == normalizedTarget)
        .toList();
  }

  void _showProfileOptions() {
    showProfileSkillsSheet(
      context,
      title: 'Responder Profile & Skills',
      primaryFieldLabel: 'Agency / Department',
      primaryFieldKey: 'agency',
      fallbackInitial: _responderName?[0].toUpperCase() ?? 'R',
      accentColor: reddiPrimaryBlue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nearbyCount = _nearbyActiveIncidents.length;

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
                        onTap: (_, __) {},
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _mapStyles[_selectedMapStyle]['url']!,
                          subdomains: const ['a', 'b', 'c', 'd'],
                          userAgentPackageName: 'com.example.disaster_response',
                        ),
                        MarkerLayer(markers: _incidentMarkers),
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
                            GestureDetector(
                              onTap: () => SettingsSheet.show(context),
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
                                child: const Icon(Icons.settings_rounded,
                                    size: 20, color: Colors.black87),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: _showNearbyIncidents,
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
                                if (nearbyCount > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFE53935),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        nearbyCount > 99
                                            ? '99+'
                                            : '$nearbyCount',
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
                                  borderRadius: BorderRadius.circular(16),
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
                                      'Police Stations',
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
                              _responderName?[0].toUpperCase() ?? 'R',
                              style: TextStyle(
                                color: reddiPrimaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
}
