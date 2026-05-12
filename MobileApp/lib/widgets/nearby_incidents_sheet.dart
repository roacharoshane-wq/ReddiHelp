import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/incident.dart';
import '../services/api_service.dart';
import '../utils/location_helper.dart';
import '../utils/parish_helper.dart';

/// Shows a modal bottom-sheet with incidents filtered to the user's parish,
/// sorted by severity (highest first) then by distance (closest first).
///
/// Call [NearbyIncidentsSheet.show] from a button press.
class NearbyIncidentsSheet extends StatefulWidget {
  const NearbyIncidentsSheet({super.key});

  /// Convenience method so callers don't need to know the widget type.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NearbyIncidentsSheet(),
    );
  }

  @override
  State<NearbyIncidentsSheet> createState() => _NearbyIncidentsSheetState();
}

class _NearbyIncidentsSheetState extends State<NearbyIncidentsSheet> {
  bool _loading = true;
  String? _error;

  String _parish = 'Unknown Parish';
  List<_IncidentWithDistance> _sorted = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Get current GPS position.
      final pos = await LocationHelper.getCurrentLocation(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 15),
      );

      // 2. Reverse-geocode to a parish using the existing helper.
      final parish = await ParishHelper()
          .getParishFromCoordinates(pos.latitude, pos.longitude);

      // 3. Fetch all incidents (uses local cache when offline).
      final all = await ApiService.getIncidents();

      // 4. Filter to the same parish (case-insensitive partial match so that
      //    "St. Andrew" matches "St Andrew", etc.).
      final parishLower = parish.toLowerCase();
      final filtered = all.where((inc) {
        return inc.areaId.toLowerCase().contains(parishLower) ||
            parishLower.contains(inc.areaId.toLowerCase());
      }).toList();

      // 5. Attach distance from current position to each incident.
      final withDist = filtered.map((inc) {
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          inc.lat,
          inc.lon,
        );
        return _IncidentWithDistance(incident: inc, distanceMeters: dist);
      }).toList();

      // 6. Sort: severity DESC (5 → 1), then distance ASC (nearest first).
      withDist.sort((a, b) {
        final bySeverity = b.incident.severity.compareTo(a.incident.severity);
        if (bySeverity != 0) return bySeverity;
        return a.distanceMeters.compareTo(b.distanceMeters);
      });

      if (mounted) {
        setState(() {
          _parish = parish;
          _sorted = withDist;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
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

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nearby Incidents',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_loading && _error == null)
                          Text(
                            'Parish: $_parish  •  ${_sorted.length} found',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            const Divider(),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : _sorted.isEmpty
                          ? _buildEmpty()
                          : ListView.builder(
                              controller: controller,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              itemCount: _sorted.length,
                              itemBuilder: (_, i) =>
                                  _IncidentTile(item: _sorted[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                color: Colors.green[400], size: 56),
            const SizedBox(height: 12),
            Text(
              'No active incidents in $_parish',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

// ─── Small data class ───────────────────────────────────────────────────────

class _IncidentWithDistance {
  final Incident incident;
  final double distanceMeters;

  const _IncidentWithDistance({
    required this.incident,
    required this.distanceMeters,
  });
}

// ─── Tile widget ─────────────────────────────────────────────────────────────

class _IncidentTile extends StatelessWidget {
  final _IncidentWithDistance item;

  const _IncidentTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final inc = item.incident;
    final distText = item.distanceMeters < 1000
        ? '${item.distanceMeters.toStringAsFixed(0)} m'
        : '${(item.distanceMeters / 1000).toStringAsFixed(1)} km';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _severityColor(inc.severity),
          child: Icon(_typeIcon(inc.type), color: Colors.white, size: 20),
        ),
        title: Row(
          children: [
            Text(
              inc.type[0].toUpperCase() + inc.type.substring(1),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            // Severity badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _severityColor(inc.severity),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'S${inc.severity}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (inc.description.isNotEmpty)
              Text(
                inc.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700]),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place, size: 14, color: Colors.grey),
                const SizedBox(width: 2),
                Text(inc.areaId,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 10),
                const Icon(Icons.near_me, size: 14, color: Colors.grey),
                const SizedBox(width: 2),
                Text(distText,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: inc.status == 'active'
                        ? Colors.orange[100]
                        : Colors.green[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    inc.status,
                    style: TextStyle(
                      fontSize: 11,
                      color: inc.status == 'active'
                          ? Colors.orange[800]
                          : Colors.green[800],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(int s) {
    if (s >= 4) return Colors.red;
    if (s >= 2) return Colors.orange;
    return Colors.green;
  }

  IconData _typeIcon(String t) {
    switch (t) {
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
