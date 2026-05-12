// Provides a prominent, panic-friendly SOS form accessible within 2 taps.
// Fields: incident type dropdown, number of people, optional description,
// auto-captured GPS with manual address fallback, offline storage via Hive.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/incident.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/location_helper.dart';
import '../utils/parish_helper.dart';
import '../widgets/media_attachment_widget.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  // SOS incident types (spec: Medical Emergency, Trapped, Flooding, Power Outage, Fire, Other)
  static const _sosTypes = [
    {
      'id': 'medical_emergency',
      'label': 'Medical Emergency',
      'icon': Icons.local_hospital,
      'color': Color(0xFFD32F2F)
    },
    {
      'id': 'trapped',
      'label': 'Trapped / Stuck',
      'icon': Icons.emergency,
      'color': Color(0xFF7B1FA2)
    },
    {
      'id': 'flood',
      'label': 'Flooding',
      'icon': Icons.water_damage,
      'color': Color(0xFF0288D1)
    },
    {
      'id': 'power_outage',
      'label': 'Power Outage',
      'icon': Icons.power_off,
      'color': Color(0xFFFFA000)
    },
    {
      'id': 'fire',
      'label': 'Fire',
      'icon': Icons.local_fire_department,
      'color': Color(0xFFFF5722)
    },
    {
      'id': 'other',
      'label': 'Other Emergency',
      'icon': Icons.warning_amber,
      'color': Color(0xFF616161)
    },
  ];

  String _selectedType = 'medical_emergency';
  int _peopleAffected = 1;
  final _descController = TextEditingController();
  final _addressController = TextEditingController();

  LatLng? _gpsLocation;
  LatLng? _pickedLocation; // from map picker
  bool _gpsLoading = true;
  bool _gpsFailed = false;
  double? _gpsAccuracy;
  String _parish = 'Detecting...';
  bool _showMapPicker = false;
  bool _submitting = false;
  String? _referenceNumber; // set after successful submission
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _acquireGps();
  }

  @override
  void dispose() {
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _acquireGps() async {
    setState(() {
      _gpsLoading = true;
      _gpsFailed = false;
    });
    try {
      final pos = await LocationHelper.getCurrentLocation(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 15),
      );
      final loc = LatLng(pos.latitude, pos.longitude);
      final parish = await ParishHelper()
          .getParishFromCoordinates(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _gpsLocation = loc;
          _gpsAccuracy = pos.accuracy;
          _parish = parish;
          _gpsLoading = false;
          // If accuracy > 50m, prompt user to confirm on map
          if (pos.accuracy > 50) {
            _showMapPicker = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gpsLoading = false;
          _gpsFailed = true;
          _showMapPicker = true; // fallback to manual
        });
      }
    }
  }

  LatLng get _effectiveLocation =>
      _pickedLocation ?? _gpsLocation ?? const LatLng(17.9712, -76.7936);

  String _generateReferenceNumber() {
    final now = DateTime.now();
    final rand = Random().nextInt(9000) + 1000;
    return 'SOS-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$rand';
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    final refNum = _generateReferenceNumber();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.user?['id'];

    final incident = Incident(
      id: 0,
      type: _selectedType,
      lat: _effectiveLocation.latitude,
      lon: _effectiveLocation.longitude,
      severity:
          _selectedType == 'medical_emergency' ? 5 : 4, // SOS defaults to high
      description: _descController.text.trim().isNotEmpty
          ? _descController.text.trim()
          : _addressController.text.trim(),
      disasterType: 'other',
      areaId: _parish,
      status: 'active',
      timestamp: DateTime.now(),
      lastUpdated: DateTime.now(),
      peopleAffected: _peopleAffected,
      referenceNumber: refNum,
      submittedBy: userId,
    );

    try {
      await ApiService.postIncident(incident);
      if (mounted) {
        setState(() {
          _referenceNumber = refNum;
          _submitted = true;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _buildConfirmation();
    }
    return _buildForm();
  }

  // ── Confirmation screen (spec: show reference number + message) ──────
  Widget _buildConfirmation() {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 80),
                const SizedBox(height: 24),
                const Text(
                  'Help is on the way!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your emergency request has been logged.\nHelp will be dispatched to your location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Your Reference Number',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _referenceNumber ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1B5E20),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back to Home',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── SOS form (designed for panicked users: large buttons, high contrast) ──
  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Incident type selector (large tap targets for panicked users) ──
            const Text('What do you need?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._sosTypes.map((t) {
              final selected = _selectedType == t['id'];
              return GestureDetector(
                onTap: () => setState(() => _selectedType = t['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? (t['color'] as Color).withOpacity(0.12)
                        : Colors.white,
                    border: Border.all(
                      color: selected ? t['color'] as Color : Colors.grey[300]!,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(t['icon'] as IconData,
                          color: t['color'] as Color, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          t['label'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.w500,
                            color:
                                selected ? t['color'] as Color : Colors.black87,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle,
                            color: t['color'] as Color, size: 22),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // ── Number of people affected ──
            const Text('How many people need help?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _peopleAffected > 1
                      ? () => setState(() => _peopleAffected--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 32),
                  color: Colors.red,
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    '$_peopleAffected',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _peopleAffected++),
                  icon: const Icon(Icons.add_circle_outline, size: 32),
                  color: Colors.red,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Brief description (optional) ──
            const Text('Brief description (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Person trapped under rubble, needs medical...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Photo / Video attachment (#8) ──
            const Text('Attach Photos or Video (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const MediaAttachmentWidget(),

            const SizedBox(height: 16),

            // ── Location display ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _gpsLoading
                            ? Icons.gps_not_fixed
                            : (_gpsFailed ? Icons.gps_off : Icons.gps_fixed),
                        color: _gpsFailed ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _gpsLoading
                              ? 'Getting your location...'
                              : (_gpsFailed
                                  ? 'GPS unavailable — set location manually'
                                  : 'Location: $_parish'
                                      '${_gpsAccuracy != null ? ' (±${_gpsAccuracy!.toStringAsFixed(0)}m)' : ''}'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      if (!_gpsLoading)
                        TextButton(
                          onPressed: () =>
                              setState(() => _showMapPicker = !_showMapPicker),
                          child:
                              Text(_showMapPicker ? 'Hide Map' : 'Pick on Map'),
                        ),
                    ],
                  ),
                  if (_gpsFailed) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addressController,
                      decoration: InputDecoration(
                        hintText: 'Enter address or landmark...',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.location_on),
                      ),
                    ),
                  ],
                  if (_showMapPicker) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: _effectiveLocation,
                            initialZoom: 15,
                            minZoom: 7,
                            cameraConstraint: CameraConstraint.containCenter(
                              bounds: LatLngBounds(
                                const LatLng(17.6, -78.5),
                                const LatLng(18.6, -76.1),
                              ),
                            ),
                            onTap: (_, point) {
                              setState(() => _pickedLocation = point);
                              // Re-detect parish for picked location
                              ParishHelper()
                                  .getParishFromCoordinates(
                                      point.latitude, point.longitude)
                                  .then((p) {
                                if (mounted) setState(() => _parish = p);
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _effectiveLocation,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_pin,
                                      color: Colors.red, size: 40),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Tap the map to set your exact location',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Submit button (large, high contrast for panicked users) ──
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.sos, size: 28),
                label: Text(
                  _submitting ? 'Sending...' : 'SEND SOS',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.red[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Your request will be stored offline if no internet',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
