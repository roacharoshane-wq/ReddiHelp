import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../providers/auth_provider.dart';
import '../models/incident.dart';
import '../widgets/sync_status_widget.dart';
import '../utils/location_helper.dart';
import '../utils/parish_helper.dart';
import 'sos_screen.dart';
import 'request_tracker_screen.dart';
import 'broadcast_alerts_screen.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/redihelp_overlays.dart';
import '../widgets/incident_marker.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const _primaryBlue = Color(0xFF1A73E8);
const _teal = Color(0xFF00BFA5);
const _orange = Color(0xFFFB8C00);
const _danger = Color(0xFFE53935);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  LatLng? _currentLatLng;
  bool _isLoadingLocation = false;
  LatLng? _pendingLocation;
  int _selectedMapStyle = 0;

  // Incident markers for victims
  List<Incident> _incidents = [];
  bool _isLoadingIncidents = false;

  // Speed dial
  bool _isDialOpen = false;
  late final AnimationController _dialController;
  late final Animation<double> _dialAnimation;

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

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    SyncService().addListener(_onSyncChange);

    // Load incidents for victims
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.userRole == 'victim') {
      _loadIncidents();
    }

    _dialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _dialAnimation = CurvedAnimation(
      parent: _dialController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSyncChange);
    _dialController.dispose();
    super.dispose();
  }

  void _onSyncChange() {}

  // ── Speed dial ──────────────────────────────────────────────────────────────

  void _toggleDial() {
    setState(() {
      _isDialOpen = !_isDialOpen;
      _isDialOpen ? _dialController.forward() : _dialController.reverse();
    });
  }

  void _closeDial() {
    if (!_isDialOpen) return;
    setState(() {
      _isDialOpen = false;
      _dialController.reverse();
    });
  }

  // Future<void> _togglePoliceStations() async {
  //   setState(() => _showPoliceStations = !_showPoliceStations);
  //   if (_showPoliceStations && _policeMarkers.isEmpty) {
  //     setState(() => _loadingPoliceStations = true);
  //     try {
  //       final stations = await ApiService.getPoliceStations();
  //       if (!mounted) return;
  //       setState(() {
  //         _policeMarkers = stations.map((station) {
  //           return Marker(
  //             point: LatLng(station.lat, station.lon),
  //             width: 40,
  //             height: 40,
  //             child: GestureDetector(
  //               onTap: () => showModalBottomSheet(
  //                 context: context,
  //                 shape: const RoundedRectangleBorder(
  //                   borderRadius:
  //                       BorderRadius.vertical(top: Radius.circular(20)),
  //                 ),
  //                 builder: (ctx) => Padding(
  //                   padding: const EdgeInsets.all(20),
  //                   child: Column(
  //                     mainAxisSize: MainAxisSize.min,
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         station.name,
  //                         style: const TextStyle(
  //                           fontSize: 20,
  //                           fontWeight: FontWeight.bold,
  //                         ),
  //                       ),
  //                       const SizedBox(height: 8),
  //                       Text('Parish: ${station.parish}'),
  //                       if (station.address != null &&
  //                           station.address!.isNotEmpty)
  //                         Text('Address: ${station.address}'),
  //                       if (station.telephone != null &&
  //                           station.telephone!.isNotEmpty)
  //                         Text('Telephone: ${station.telephone}'),
  //                     ],
  //                   ),
  //                 ),
  //               ),
  //               child: Stack(
  //                 alignment: Alignment.center,
  //                 children: [
  //                   const Icon(Icons.location_on,
  //                       color: _primaryBlue, size: 40),
  //                   Container(
  //                     width: 18,
  //                     height: 18,
  //                     decoration: const BoxDecoration(
  //                       shape: BoxShape.circle,
  //                       color: Colors.white,
  //                     ),
  //                     child: const Icon(Icons.local_police,
  //                         color: _primaryBlue, size: 12),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //           );
  //         }).toList();
  //         _loadingPoliceStations = false;
  //       });
  //     } catch (_) {
  //       if (mounted) {
  //         setState(() => _loadingPoliceStations = false);
  //       }
  //     }
  //   }
  // }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final pos = await LocationHelper.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentLatLng = LatLng(pos.latitude, pos.longitude);
          _isLoadingLocation = false;
        });
        _mapController.move(_currentLatLng!, 14);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  // ── Incident loading ────────────────────────────────────────────────────────

  Future<void> _loadIncidents() async {
    setState(() => _isLoadingIncidents = true);
    try {
      final user = await AuthService().getUser();
      final currentUserId = user?['id'] as int?;
      final currentUserPhone = user?['phone'] as String?;

      final serverIncidents = await ApiService.getIncidents();
      final localIncidents = SyncService()
          .getLocalIncidents()
          .map((e) => Incident.fromJson(e))
          .toList();

      final serverIds = serverIncidents.map((i) => i.id).toSet();
      final mergedIncidents = [
        ...serverIncidents,
        ...localIncidents.where((li) => !serverIds.contains(li.id)),
      ];

      final filteredIncidents = mergedIncidents.where((inc) {
        if (currentUserId != null && inc.submittedBy == currentUserId) {
          return true;
        }
        if (currentUserPhone != null && inc.victimPhone == currentUserPhone) {
          return true;
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _incidents = filteredIncidents;
          _isLoadingIncidents = false;
        });
      }
    } catch (e) {
      print('❌ [MapScreen] Failed to load incidents: $e');
      if (mounted) setState(() => _isLoadingIncidents = false);
    }
  }

  List<Marker> _buildIncidentMarkers(BuildContext context) {
    return _incidents
        .map((inc) => IncidentMarker(incident: inc).toMarker(context))
        .toList();
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Provider.of<AuthProvider>(context, listen: false).logout();
    }
  }

  // ── Incident flow ───────────────────────────────────────────────────────────

  void _openIncidentPicker({LatLng? customLocation}) {
    _pendingLocation = customLocation;
    _closeDial();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _IncidentTypePicker(
        onTypeSelected: (type) {
          Navigator.pop(context);
          _openReportForm(type);
        },
      ),
    );
  }

  void _openReportForm(_IncidentTypeOption type) {
    final location =
        _pendingLocation ?? _currentLatLng ?? const LatLng(17.9712, -76.7936);
    _pendingLocation = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _IncidentReportForm(
        type: type,
        location: location,
        onSubmit: _submitIncident,
      ),
    );
  }

  Future<void> _submitIncident(Incident incident) async {
    print('🚀 [MapScreen] Submitting: ${incident.type}');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Submitting...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      await ApiService.postIncident(incident);
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        await _loadIncidents();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Report submitted'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final syncService = SyncService();

    return Scaffold(
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(17.9712, -76.7936),
              initialZoom: 12,
              maxZoom: 19,
              minZoom: 7,
              cameraConstraint: CameraConstraint.containCenter(
                bounds: LatLngBounds(
                  const LatLng(17.6, -78.5),
                  const LatLng(18.6, -76.1),
                ),
              ),
              onLongPress: (tapPosition, point) {
                print('📍 [MapScreen] Long press at $point');
                _openIncidentPicker(customLocation: point);
              },
              onTap: (_, __) => _closeDial(),
            ),
            children: [
              TileLayer(
                urlTemplate: _mapStyles[_selectedMapStyle]['url']!,
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'com.example.disaster_response',
              ),
              // if (_showPoliceStations && _policeMarkers.isNotEmpty)
              //   MarkerLayer(markers: _policeMarkers),
              if (_currentLatLng != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLatLng!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
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
              // Incident markers for victims
              if (Provider.of<AuthProvider>(context).userRole == 'victim' &&
                  _incidents.isNotEmpty)
                MarkerLayer(markers: _buildIncidentMarkers(context)),
            ],
          ),

          // ── Backdrop (dims map when dial is open) ────────────────────────
          AnimatedBuilder(
            animation: _dialAnimation,
            builder: (_, __) {
              final opacity = _dialAnimation.value * 0.28;
              if (opacity == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: GestureDetector(
                  onTap: _closeDial,
                  child: Container(color: Colors.black.withOpacity(opacity)),
                ),
              );
            },
          ),

          // ── Top-right: map style, guide, police pills ───────────────────
          Positioned(
            top: 0,
            right: 12,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedMapStyle =
                          (_selectedMapStyle + 1) % _mapStyles.length;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.13),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_outlined,
                              size: 18, color: Colors.black87),
                          const SizedBox(width: 6),
                          Text(
                            _mapStyles[_selectedMapStyle]['name']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => showPreparednessGuideSheet(
                      context,
                      victimMode: true,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.13),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_outlined,
                              size: 18, color: _teal),
                          SizedBox(width: 6),
                          Text(
                            'View Guide',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _teal,
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

          // ── Top-left: pill card (locate · logout · settings) ─────────────
          Positioned(
            top: 0,
            left: 12,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pillIconButton(
                      icon: _isLoadingLocation
                          ? Icons.gps_not_fixed
                          : Icons.my_location_rounded,
                      onTap: _getCurrentLocation,
                      tooltip: 'My location',
                    ),
                    _pillDivider(),
                    _pillIconButton(
                      icon: Icons.campaign_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BroadcastAlertsScreen()),
                      ),
                      tooltip: 'Broadcast alerts',
                    ),
                    _pillDivider(),
                    _pillIconButton(
                      icon: Icons.logout_rounded,
                      onTap: _logout,
                      tooltip: 'Logout',
                    ),
                    _pillDivider(),
                    _pillIconButton(
                      icon: Icons.settings_rounded,
                      onTap: () => SettingsSheet.show(context),
                      tooltip: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Sync status pill ─────────────────────────────────────────────
          Positioned(
            top: 164,
            right: 12,
            child: ListenableBuilder(
              listenable: syncService,
              builder: (context, _) => const SyncStatusWidget(),
            ),
          ),

          // ── Incident loading indicator for victims ─────────────────────────
          if (Provider.of<AuthProvider>(context).userRole == 'victim' &&
              _isLoadingIncidents)
            Positioned(
              top: 200,
              right: 12,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.13),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Loading incidents...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom-right: speed dial + SOS ───────────────────────────────
          Positioned(
            bottom: 32,
            right: 20,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Speed dial children — rendered top-to-bottom (furthest→closest)
                  _buildDialChild(
                    staggerIndex: 2,
                    icon: Icons.list_alt_rounded,
                    label: 'My Requests',
                    color: _teal,
                    onTap: () {
                      _closeDial();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RequestTrackerScreen()),
                      );
                    },
                  ),
                  _buildDialChild(
                    staggerIndex: 1,
                    icon: Icons.campaign_rounded,
                    label: 'Broadcast Alert',
                    color: _orange,
                    onTap: () {
                      _closeDial();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BroadcastAlertsScreen()),
                      );
                    },
                  ),

                  // Report at current map center (acts like long-press)
                  _buildDialChild(
                    staggerIndex: 0,
                    icon: Icons.location_on_rounded,
                    label: 'Report Here',
                    color: _primaryBlue,
                    onTap: () {
                      _closeDial();
                      // Use current device location when available; fall back to default.
                      // Note: some flutter_map versions don't expose a `center` getter
                      // on MapController, so avoid referencing it to prevent analyzer errors.
                      final center =
                          _currentLatLng ?? const LatLng(17.9712, -76.7936);
                      _openIncidentPicker(customLocation: center);
                    },
                  ),

                  const SizedBox(height: 12),

                  // Main FAB — + icon, rotates to × when open
                  GestureDetector(
                    onTap: _toggleDial,
                    onLongPress: _toggleDial,
                    child: AnimatedBuilder(
                      animation: _dialAnimation,
                      builder: (_, __) => Transform.rotate(
                        angle: _dialAnimation.value * 0.7854, // 45°
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _primaryBlue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _primaryBlue.withOpacity(0.38),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // SOS — always visible, never obscured by dial backdrop
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SosScreen()),
                    ),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _danger,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: _danger.withOpacity(0.38),
                            blurRadius: 14,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Speed dial child widget ─────────────────────────────────────────────────
  //
  // [staggerIndex] 0 = closest to FAB (appears first), 2 = furthest (appears last).

  Widget _buildDialChild({
    required int staggerIndex,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _dialAnimation,
      builder: (_, __) {
        // Each child starts its animation slightly after the previous one.
        final raw = _dialAnimation.value - (staggerIndex * 0.12);
        final progress = Curves.easeOutBack.transform(raw.clamp(0.0, 1.0));

        if (progress == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Opacity(
            opacity: progress.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: progress,
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Label pill
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Action icon
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Pill card helpers ───────────────────────────────────────────────────────

  Widget _pillIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _pillDivider() => Container(
        width: 22,
        height: 0.5,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: Colors.grey.withOpacity(0.30),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Incident type picker  (unchanged – only comments trimmed)
// ─────────────────────────────────────────────────────────────────────────────

class _IncidentTypeOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _IncidentTypeOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}

const _incidentTypes = [
  _IncidentTypeOption(
    id: 'road_hazard',
    label: 'Road Hazard',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFE07B2A),
  ),
  _IncidentTypeOption(
    id: 'construction',
    label: 'Construction',
    icon: Icons.construction,
    color: Color(0xFFD4A017),
  ),
  _IncidentTypeOption(
    id: 'traffic_accident',
    label: 'Traffic Accident',
    icon: Icons.directions_car,
    color: Color(0xFFD94040),
  ),
  _IncidentTypeOption(
    id: 'power_outage',
    label: 'Power Outage',
    icon: Icons.bolt,
    color: Color(0xFF3A78C9),
  ),
  _IncidentTypeOption(
    id: 'tree_down',
    label: 'Tree Down',
    icon: Icons.park,
    color: Color(0xFF2E8B57),
  ),
  _IncidentTypeOption(
    id: 'flood',
    label: 'Flooding',
    icon: Icons.water_drop,
    color: Color(0xFF2196A6),
  ),
  _IncidentTypeOption(
    id: 'medical',
    label: 'Medical',
    icon: Icons.local_hospital,
    color: Colors.red,
  ),
  _IncidentTypeOption(
    id: 'fire',
    label: 'Fire',
    icon: Icons.local_fire_department,
    color: Colors.deepOrange,
  ),
  _IncidentTypeOption(
    id: 'trapped',
    label: 'Trapped',
    icon: Icons.emergency,
    color: Colors.purple,
  ),
  _IncidentTypeOption(
    id: 'other',
    label: 'Other',
    icon: Icons.more_horiz,
    color: Colors.grey,
  ),
];

class _IncidentTypePicker extends StatelessWidget {
  final ValueChanged<_IncidentTypeOption> onTypeSelected;

  const _IncidentTypePicker({required this.onTypeSelected});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _incidentTypes.length,
              itemBuilder: (_, i) {
                final t = _incidentTypes[i];
                return GestureDetector(
                  onTap: () => onTypeSelected(t),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon, color: t.color, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          t.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Incident report form  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _IncidentReportForm extends StatefulWidget {
  final _IncidentTypeOption type;
  final LatLng location;
  final Future<void> Function(Incident) onSubmit;

  const _IncidentReportForm({
    required this.type,
    required this.location,
    required this.onSubmit,
  });

  @override
  State<_IncidentReportForm> createState() => _IncidentReportFormState();
}

class _IncidentReportFormState extends State<_IncidentReportForm> {
  final _descController = TextEditingController();
  double _severity = 5;
  bool _isSubmitting = false;
  String _parish = 'Detecting...';
  String _disasterType = 'other';

  final List<String> _disasterTypes = [
    'hurricane',
    'earthquake',
    'flood',
    'fire',
    'tornado',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _detectParish();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _detectParish() async {
    final p = await ParishHelper().getParishFromCoordinates(
      widget.location.latitude,
      widget.location.longitude,
    );
    if (mounted) setState(() => _parish = p);
  }

  String get _severityLabel {
    if (_severity <= 3) return 'Low';
    if (_severity <= 7) return 'Medium';
    return 'High';
  }

  int get _backendSeverity => (_severity / 2).ceil().clamp(1, 5);

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final incident = Incident(
      id: 0,
      type: widget.type.id,
      lat: widget.location.latitude,
      lon: widget.location.longitude,
      severity: _backendSeverity,
      description: _descController.text.trim(),
      disasterType: _disasterType,
      areaId: _parish,
      status: 'active',
      timestamp: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    await widget.onSubmit(incident);
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            builder: (_) =>
                                _IncidentTypePicker(onTypeSelected: (_) {}),
                          );
                        },
                        child: const Icon(Icons.arrow_back,
                            size: 22, color: Colors.black87),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.type.label,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'What caused the incident?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _disasterType,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down),
                        items: _disasterTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(
                              type[0].toUpperCase() + type.substring(1),
                              style: const TextStyle(fontSize: 15),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) =>
                            setState(() => _disasterType = val!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Describe the issue...',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 14),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Severity',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        '$_severityLabel (${_severity.round()}/10)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.black87,
                      inactiveTrackColor: Colors.grey[300],
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 12, elevation: 3),
                      overlayColor: Colors.black12,
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: _severity,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (v) => setState(() => _severity = v),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Low',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('Medium',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('High',
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2C),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[400],
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
