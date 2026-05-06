import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/incident.dart';
import '../utils/parish_helper.dart';

class IncidentForm extends StatefulWidget {
  final LatLng initialLocation;
  final Function(Incident) onSubmit;
  final String incidentType;

  const IncidentForm({
    super.key,
    required this.initialLocation,
    required this.onSubmit,
    required this.incidentType,
  });

  @override
  _IncidentFormState createState() => _IncidentFormState();
}

class _IncidentFormState extends State<IncidentForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _typeController;
  late TextEditingController _parishController;

  // Form values
  late String _type;
  late String _disasterType;
  late int _severity;
  late String _description;
  late String _areaId;

  bool _isDetectingParish = true;
  bool _debugMode = true; // Set to false to disable debug logs

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

    _debugLog('🔧 INITIALIZATION STARTED');
    _debugLog('📱 Widget params:');
    _debugLog('   - incidentType: ${widget.incidentType}');
    _debugLog(
        '   - location: (${widget.initialLocation.latitude}, ${widget.initialLocation.longitude})');

    // Initialize with values from widget
    _type = widget.incidentType;
    _disasterType = 'other';
    _severity = 3;
    _description = '';
    _areaId = 'Detecting...';

    // Initialize controllers
    _typeController =
        TextEditingController(text: _getDisplayIncidentType(_type));
    _parishController = TextEditingController(text: _areaId);

    _debugLog('✅ Controllers initialized');
    _debugLog('   - Type controller: ${_typeController.text}');
    _debugLog('   - Parish controller: ${_parishController.text}');

    // Run diagnostic tests
    _runDiagnosticTests();

    // Detect parish
    _detectParish();
  }

  @override
  void dispose() {
    _debugLog('🧹 DISPOSING FORM');
    _typeController.dispose();
    _parishController.dispose();
    super.dispose();
  }

  void _debugLog(String message) {
    if (_debugMode) {
      print('🔍 [IncidentForm] $message');
    }
  }

  Future<void> _runDiagnosticTests() async {
    _debugLog('🧪 RUNNING DIAGNOSTIC TESTS');

    final helper = ParishHelper();

    // Test 1: Check if GeoJSON is loaded
    _debugLog('Test 1: Checking GeoJSON load status');
    final hasBoundaries = helper.hasAccurateBoundaries;
    _debugLog('   - Has accurate boundaries: $hasBoundaries');

    if (hasBoundaries) {
      final loadedParishes = helper.getLoadedParishNames();
      _debugLog('   - Loaded parishes: $loadedParishes');
    } else {
      _debugLog('   - ⚠️ No accurate boundaries loaded, will use fallback');
    }

    // Test 2: Test known locations
    _debugLog('Test 2: Testing known locations');

    final testLocations = [
      {'name': 'Kingston', 'lat': 17.9712, 'lon': -76.7936},
      {'name': 'Montego Bay', 'lat': 18.4667, 'lon': -77.9167},
      {'name': 'Spanish Town', 'lat': 17.9833, 'lon': -76.9500},
      {'name': 'Port Antonio', 'lat': 18.1761, 'lon': -76.4506},
      {'name': 'Negril', 'lat': 18.2730, 'lon': -78.3486},
    ];

    for (var loc in testLocations) {
      try {
        final result = await helper.getParishFromCoordinates(
            loc['lat'] as double, loc['lon'] as double);
        _debugLog('   - ${loc['name']}: $result');
      } catch (e) {
        _debugLog('   - ❌ ${loc['name']} error: $e');
      }
    }

    // Test 3: Test current location
    _debugLog('Test 3: Testing current location');
    _debugLog(
        '   - Current: (${widget.initialLocation.latitude}, ${widget.initialLocation.longitude})');

    // Test 4: Check fallback directly
    _debugLog('Test 4: Testing fallback method directly');
    final fallbackResult = helper.getApproximateParish(
      widget.initialLocation.latitude,
      widget.initialLocation.longitude,
    );
    _debugLog('   - Fallback result: $fallbackResult');

    _debugLog('🧪 DIAGNOSTIC TESTS COMPLETE');
  }

  // Helper to format incident type for display
  String _getDisplayIncidentType(String type) {
    switch (type) {
      case 'medical':
        return '🚑 Medical Emergency';
      case 'fire':
        return '🔥 Fire Emergency';
      case 'flood':
        return '💧 Flood Emergency';
      case 'trapped':
        return '🚶 Trapped/Rescue';
      case 'other':
        return '⚠️ Other Emergency';
      default:
        return type;
    }
  }

  // Get icon for incident type
  IconData _getTypeIcon(String type) {
    switch (type) {
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

  // Get color for incident type
  Color _getTypeColor(String type) {
    switch (type) {
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'flood':
        return Colors.blue;
      case 'trapped':
        return Colors.purple;
      case 'other':
      default:
        return Colors.grey;
    }
  }

  Future<void> _detectParish() async {
    if (!mounted) return;

    setState(() {
      _isDetectingParish = true;
      _areaId = 'Detecting...';
      _parishController.text = 'Detecting...';
    });

    try {
      final parish = await ParishHelper().getParishFromCoordinates(
        widget.initialLocation.latitude,
        widget.initialLocation.longitude,
      );

      if (mounted) {
        setState(() {
          _areaId = parish;
          _parishController.text = parish;
          _isDetectingParish = false;
        });
      }
    } catch (e) {
      print('❌ Parish detection error: $e');
      if (mounted) {
        setState(() {
          _areaId = 'Error Detecting';
          _parishController.text = 'Error Detecting';
          _isDetectingParish = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _debugLog('🔄 BUILDING FORM');
    _debugLog('   - _type: $_type');
    _debugLog('   - _areaId: $_areaId');
    _debugLog('   - _isDetectingParish: $_isDetectingParish');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Debug toggle (optional - can be removed in production)
            // if (_debugMode)
            //   Container(
            //     margin: const EdgeInsets.only(bottom: 8),
            //     padding: const EdgeInsets.all(8),
            //     decoration: BoxDecoration(
            //       color: Colors.grey[900],
            //       borderRadius: BorderRadius.circular(8),
            //     ),
            //     child: Row(
            //       children: [
            //         Icon(Icons.bug_report, size: 16, color: Colors.green[300]),
            //         const SizedBox(width: 8),
            //         Expanded(
            //           child: Text(
            //             'Debug Mode ON',
            //             style: TextStyle(
            //               color: Colors.green[300],
            //               fontSize: 12,
            //               fontFamily: 'monospace',
            //             ),
            //           ),
            //         ),
            //         TextButton(
            //           onPressed: () {
            //             setState(() {
            //               _debugMode = !_debugMode;
            //             });
            //           },
            //           child: const Text('Hide', style: TextStyle(fontSize: 10)),
            //         ),
            //       ],
            //     ),
            //   ),

            // Header with type icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getTypeColor(_type).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getTypeIcon(_type),
                    color: _getTypeColor(_type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Report Incident',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getDisplayIncidentType(_type),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Location card with parish prominently displayed
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Parish display (prominent)
                            Row(
                              children: [
                                Text(
                                  _isDetectingParish
                                      ? 'Detecting parish...'
                                      : _areaId,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isDetectingParish)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                if (!_isDetectingParish &&
                                    _areaId != 'Unknown Parish')
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                  ),
                                if (!_isDetectingParish &&
                                    _areaId == 'Unknown Parish')
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.error,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Coordinates (smaller text)
                            Text(
                              '${widget.initialLocation.latitude.toStringAsFixed(5)}, '
                              '${widget.initialLocation.longitude.toStringAsFixed(5)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Debug info (only visible in debug mode)
                  // if (_debugMode && !_isDetectingParish) ...[
                  //   const SizedBox(height: 12),
                  //   Container(
                  //     padding: const EdgeInsets.all(8),
                  //     decoration: BoxDecoration(
                  //       color: Colors.grey[900],
                  //       borderRadius: BorderRadius.circular(8),
                  //     ),
                  //     child: Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         Text(
                  //           '🔍 Debug Info:',
                  //           style: TextStyle(
                  //             color: Colors.green[300],
                  //             fontSize: 11,
                  //             fontWeight: FontWeight.bold,
                  //           ),
                  //         ),
                  //         const SizedBox(height: 4),
                  //         Text(
                  //           'Parish: $_areaId',
                  //           style: TextStyle(
                  //             color: Colors.green[300],
                  //             fontSize: 11,
                  //             fontFamily: 'monospace',
                  //           ),
                  //         ),
                  //         Text(
                  //           'Coordinates: (${widget.initialLocation.latitude.toStringAsFixed(6)}, ${widget.initialLocation.longitude.toStringAsFixed(6)})',
                  //           style: TextStyle(
                  //             color: Colors.green[300],
                  //             fontSize: 11,
                  //             fontFamily: 'monospace',
                  //           ),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  // ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Disaster Type Dropdown
            DropdownButtonFormField<String>(
              initialValue: _disasterType,
              decoration: const InputDecoration(
                labelText: 'Disaster Context',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cloud),
              ),
              items: _disasterTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type[0].toUpperCase() + type.substring(1)),
                );
              }).toList(),
              onChanged: (val) {
                _debugLog('📋 Disaster type changed to: $val');
                setState(() => _disasterType = val!);
              },
            ),
            const SizedBox(height: 16),

            // Severity Slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Severity (1-5)',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _severity.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: _severity.toString(),
                        onChanged: (val) {
                          setState(() => _severity = val.round());
                          _debugLog('📊 Severity changed to: $_severity');
                        },
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getSeverityColor(_severity),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$_severity',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Describe the situation...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              onSaved: (val) => _description = val ?? '',
              onChanged: (val) =>
                  _debugLog('📝 Description updated (${val.length} chars)'),
            ),
            const SizedBox(height: 24),

            // Retry button (if detection failed)
            if (!_isDetectingParish && _areaId == 'Unknown Parish')
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _debugLog('🔄 Manual retry triggered');
                      _detectParish();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Parish Detection'),
                  ),
                ),
              ),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isDetectingParish ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getTypeColor(_type),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_getTypeIcon(_type)),
                    const SizedBox(width: 8),
                    Text(_isDetectingParish
                        ? 'Detecting Parish...'
                        : (_areaId == 'Unknown Parish'
                            ? 'Submit Anyway?'
                            : 'Submit Report')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _submit() {
    _debugLog('📤 SUBMIT BUTTON PRESSED');
    _debugLog('   - Form validation: ${_formKey.currentState?.validate()}');

    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      _debugLog('✅ FORM VALIDATION PASSED');
      _debugLog('📋 FINAL FORM VALUES:');
      _debugLog('   - Type: $_type');
      _debugLog('   - Disaster: $_disasterType');
      _debugLog('   - Severity: $_severity');
      _debugLog('   - Parish: $_areaId');
      _debugLog(
          '   - Description: "${_description.length > 50 ? "${_description.substring(0, 50)}..." : _description}"');
      _debugLog(
          '   - Coordinates: (${widget.initialLocation.latitude}, ${widget.initialLocation.longitude})');

      final incident = Incident(
        id: 0,
        type: _type,
        lat: widget.initialLocation.latitude,
        lon: widget.initialLocation.longitude,
        severity: _severity,
        description: _description,
        disasterType: _disasterType,
        areaId: _areaId,
        status: 'active',
        timestamp: DateTime.now(),
        lastUpdated: DateTime.now(),
      );

      _debugLog('🚀 Calling onSubmit callback');
      widget.onSubmit(incident);
    } else {
      _debugLog('❌ FORM VALIDATION FAILED');
    }
  }

  Color _getSeverityColor(int severity) {
    if (severity >= 4) return Colors.red;
    if (severity >= 2) return Colors.orange;
    return Colors.green;
  }
}
