import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/police_station.dart';
import '../services/api_service.dart';
import '../utils/location_helper.dart';

class VolunteerCheckInScreen extends StatefulWidget {
  const VolunteerCheckInScreen({super.key});

  @override
  State<VolunteerCheckInScreen> createState() => _VolunteerCheckInScreenState();
}

class _VolunteerCheckInScreenState extends State<VolunteerCheckInScreen> {
  final MapController _mapController = MapController();
  final LatLng _defaultCenter = const LatLng(18.1096, -77.2975);

  bool _loading = true;
  bool _showStationPoints = true;
  bool _mapReady = false;
  bool _submittingCheckIn = false;
  String? _error;

  List<PoliceStation> _stations = [];
  _CheckInRecommendation? _recommendation;
  DateTime? _checkedInAt;
  String? _checkedInStation;

  @override
  void initState() {
    super.initState();
    _loadCheckInData();
  }

  Future<void> _loadCheckInData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final stations = await ApiService.getPoliceStations();
      final anchorSnapshot = await ApiService.getMyLocationAnchor();
      final anchor = await _resolveAnchorLocation(anchorSnapshot);
      final recommendation = _selectNearestStation(anchor, stations);

      if (!mounted) return;
      setState(() {
        _stations = stations;
        _recommendation = recommendation;
        _checkedInAt = _toDateTime(anchorSnapshot?['checked_in_at']);
        _checkedInStation =
            _toStringValue(anchorSnapshot?['check_in_station_name']);
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerMapOnAnchor();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load check-in recommendation: $e';
      });
    }
  }

  Future<_AnchorLocation> _resolveAnchorLocation(
      Map<String, dynamic>? anchorSnapshot) async {
    final savedLat = _toDouble(anchorSnapshot?['last_lat']);
    final savedLon = _toDouble(anchorSnapshot?['last_lon']);
    if (savedLat != null && savedLon != null) {
      return _AnchorLocation(
        lat: savedLat,
        lon: savedLon,
        sourceLabel: 'Saved DB location (last_lat/last_lon)',
        isFallback: false,
      );
    }

    final activeLat = _toDouble(anchorSnapshot?['active_location_lat']);
    final activeLon = _toDouble(anchorSnapshot?['active_location_lon']);
    if (activeLat != null && activeLon != null) {
      return _AnchorLocation(
        lat: activeLat,
        lon: activeLon,
        sourceLabel: 'Fallback from active profile location',
        isFallback: true,
      );
    }

    final gps = await LocationHelper.getCurrentLocation(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 15),
    );
    return _AnchorLocation(
      lat: gps.latitude,
      lon: gps.longitude,
      sourceLabel: 'Fallback from current GPS location',
      isFallback: true,
    );
  }

  _CheckInRecommendation? _selectNearestStation(
    _AnchorLocation anchor,
    List<PoliceStation> stations,
  ) {
    if (stations.isEmpty) return null;

    PoliceStation nearest = stations.first;
    double nearestMeters = Geolocator.distanceBetween(
      anchor.lat,
      anchor.lon,
      nearest.lat,
      nearest.lon,
    );

    for (final station in stations.skip(1)) {
      final meters = Geolocator.distanceBetween(
        anchor.lat,
        anchor.lon,
        station.lat,
        station.lon,
      );
      if (meters < nearestMeters) {
        nearest = station;
        nearestMeters = meters;
      }
    }

    return _CheckInRecommendation(
      anchor: anchor,
      station: nearest,
      distanceMeters: nearestMeters,
    );
  }

  Future<void> _confirmCheckIn(PoliceStation station) async {
    if (_submittingCheckIn) return;

    setState(() => _submittingCheckIn = true);
    try {
      final result = await ApiService.submitVolunteerCheckIn(
        stationName: station.name,
        parish: station.parish,
        lat: station.lat,
        lon: station.lon,
      );

      if (result == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save check-in. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _checkedInAt = _toDateTime(result['checked_in_at']) ?? DateTime.now();
        _checkedInStation =
            _toStringValue(result['check_in_station_name']) ?? station.name;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checked in at ${station.name}.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save check-in.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingCheckIn = false);
      }
    }
  }

  void _centerMapOnAnchor() {
    if (!_mapReady || _recommendation == null) return;
    final anchor = _recommendation!.anchor;
    _mapController.move(LatLng(anchor.lat, anchor.lon), 11.8);
  }

  List<Marker> _buildStationMarkers() {
    if (!_showStationPoints) return [];

    final nearest = _recommendation?.station;
    return _stations.map((station) {
      final isNearest = nearest != null &&
          station.name == nearest.name &&
          station.lat == nearest.lat &&
          station.lon == nearest.lon;

      return Marker(
        point: LatLng(station.lat, station.lon),
        width: isNearest ? 56 : 44,
        height: isNearest ? 56 : 44,
        child: GestureDetector(
          onTap: () => _showStationDetails(station),
          child: Container(
            decoration: BoxDecoration(
              color: isNearest ? Colors.orange : Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: isNearest ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isNearest ? Icons.star : Icons.local_police,
              color: Colors.white,
              size: isNearest ? 24 : 20,
            ),
          ),
        ),
      );
    }).toList();
  }

  Marker? _buildAnchorMarker() {
    final recommendation = _recommendation;
    if (recommendation == null) return null;

    return Marker(
      point: LatLng(recommendation.anchor.lat, recommendation.anchor.lon),
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 18),
      ),
    );
  }

  Future<void> _openDirections(PoliceStation station) async {
    final recommendation = _recommendation;
    if (recommendation == null) return;

    final origin = '${recommendation.anchor.lat},${recommendation.anchor.lon}';
    final destination = '${station.lat},${station.lon}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Google Maps directions.')),
    );
  }

  void _showStationDetails(PoliceStation station) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Parish: ${station.parish}'),
            if (station.address != null && station.address!.isNotEmpty)
              Text('Address: ${station.address}'),
            if (station.telephone != null && station.telephone!.isNotEmpty)
              Text('Telephone: ${station.telephone}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _confirmCheckIn(station);
                },
                icon: const Icon(Icons.verified_user),
                label: const Text('Check In Here'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openDirections(station);
                },
                icon: const Icon(Icons.directions),
                label: const Text('Open Directions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationCard() {
    final recommendation = _recommendation;
    if (recommendation == null) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No recommendation available right now. Pull to refresh and try again.',
          ),
        ),
      );
    }

    final station = recommendation.station;
    final sourceLabel = recommendation.anchor.isFallback
        ? 'Source: fallback'
        : 'Source: saved DB';
    final checkedInAt = _checkedInAt;
    final checkedInStation = _checkedInStation;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recommended Police Station for Volunteer Check-In',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'All volunteers should check in at their nearest station before deployment.',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.blue,
                  child:
                      Icon(Icons.local_police, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Parish: ${station.parish}',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    LocationHelper.formatDistance(
                        recommendation.distanceMeters),
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(label: Text(sourceLabel)),
                Chip(label: Text(recommendation.anchor.sourceLabel)),
              ],
            ),
            if (checkedInAt != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Checked in at ${checkedInStation ?? 'station'} on ${_formatTimestamp(checkedInAt)}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _submittingCheckIn ? null : () => _confirmCheckIn(station),
                icon: const Icon(Icons.verified_user),
                label: Text(
                  checkedInAt == null
                      ? 'Confirm Check-In at This Station'
                      : 'Update Check-In to This Station',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openDirections(station),
                icon: const Icon(Icons.directions),
                label: const Text('Open Route in Google Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPanel() {
    final anchor = _recommendation?.anchor;
    final anchorMarker = _buildAnchorMarker();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: anchor != null
                    ? LatLng(anchor.lat, anchor.lon)
                    : _defaultCenter,
                initialZoom: 11.8,
                minZoom: 7,
                onMapReady: () {
                  setState(() => _mapReady = true);
                  _centerMapOnAnchor();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.disaster_response',
                ),
                if (_showStationPoints)
                  MarkerLayer(markers: _buildStationMarkers()),
                if (anchorMarker != null) MarkerLayer(markers: [anchorMarker]),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _showStationPoints = !_showStationPoints;
                  });
                },
                icon: Icon(
                  _showStationPoints ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                label: Text(
                  _showStationPoints ? 'Hide stations' : 'Show stations',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'volunteer_checkin_center',
                onPressed: _centerMapOnAnchor,
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String? _toStringValue(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Volunteer Check-In')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final showErrorOnly = _error != null && _recommendation == null;
    if (showErrorOnly) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Volunteer Check-In'),
          actions: [
            IconButton(
              onPressed: _loadCheckInData,
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _loadCheckInData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Volunteer Check-In'),
        actions: [
          IconButton(
            onPressed: _loadCheckInData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRecommendationCard(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            ),
          Expanded(child: _buildMapPanel()),
        ],
      ),
    );
  }
}

class _AnchorLocation {
  final double lat;
  final double lon;
  final String sourceLabel;
  final bool isFallback;

  const _AnchorLocation({
    required this.lat,
    required this.lon,
    required this.sourceLabel,
    required this.isFallback,
  });
}

class _CheckInRecommendation {
  final _AnchorLocation anchor;
  final PoliceStation station;
  final double distanceMeters;

  const _CheckInRecommendation({
    required this.anchor,
    required this.station,
    required this.distanceMeters,
  });
}
