import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/incident.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/location_helper.dart';
import '../widgets/settings_sheet.dart';

class VolunteerTasksScreen extends StatefulWidget {
  const VolunteerTasksScreen({super.key});

  @override
  State<VolunteerTasksScreen> createState() => _VolunteerTasksScreenState();
}

class _VolunteerTasksScreenState extends State<VolunteerTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Incident> _availableTasks = []; // active incidents needing help
  List<Incident> _myActiveTasks = []; // accepted / in-progress
  List<Incident> _completedTasks = []; // resolved by this volunteer
  bool _loading = true;
  Position? _currentPosition;

  // Arrival geofencing
  StreamSubscription<Position>? _arrivalSubscription;
  bool _arrivalDialogShown = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _arrivalSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final userId = auth.user?['id'];

      _currentPosition = await LocationHelper.getCurrentLocation(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );

      // Fetch recommended tasks (nearby active incidents sorted by
      // severity + distance on the server) for the Available tab.
      List<Incident> available = [];
      if (_currentPosition != null) {
        available = await ApiService.getRecommendedTasks(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }

      // Fetch all incidents for active (active/in-progress) and completed (resolved).
      final allIncidents = await ApiService.getIncidents();
      final active = allIncidents
          .where((i) =>
              (i.status == 'active' || i.status == 'in-progress') &&
              i.assignedTo == userId)
          .toList();
      final completed = allIncidents
          .where((i) => i.status == 'resolved' && i.assignedTo == userId)
          .toList();

      if (mounted) {
        setState(() {
          _availableTasks = available;
          _myActiveTasks = active;
          _completedTasks = completed;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _acceptTask(Incident incident) async {
    // Optimistic: move to My Tasks immediately
    setState(() {
      _availableTasks.remove(incident);
      _myActiveTasks.insert(0, incident.copyWith(status: 'in-progress'));
    });

    // Start arrival geofencing for this task
    _startArrivalMonitoring(incident);

    final success =
        await ApiService.updateIncidentStatus(incident.id, 'in-progress');
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Update queued — will sync when online'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ── Arrival geofencing: monitor position and trigger dialog at ≤100m ──
  void _startArrivalMonitoring(Incident incident) {
    _arrivalSubscription?.cancel();
    _arrivalDialogShown = false;

    _arrivalSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((position) {
      if (_arrivalDialogShown || !mounted) return;
      final distMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        incident.lat,
        incident.lon,
      );
      if (distMeters <= 100) {
        _arrivalDialogShown = true;
        _arrivalSubscription?.cancel();
        _showArrivalDialog(incident);
      }
    });
  }

  void _showArrivalDialog(Incident incident) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Have you arrived?'),
        content: const Text(
          'You appear to be within 100m of the incident location. '
          'Confirm your arrival to update the status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not yet'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _progressTask(incident, 'on-scene');
            },
            icon: const Icon(Icons.check),
            label: const Text('Yes, I arrived'),
          ),
        ],
      ),
    );
  }

  void _declineTask(Incident incident) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Task declined — reassigned to next volunteer'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  Future<void> _progressTask(Incident incident, String newStatus) async {
    // Optimistic update
    setState(() {
      final idx = _myActiveTasks.indexWhere((t) => t.id == incident.id);
      if (idx != -1) {
        if (newStatus == 'resolved') {
          _myActiveTasks.removeAt(idx);
          _completedTasks.insert(0, incident.copyWith(status: 'resolved'));
        } else {
          _myActiveTasks[idx] = incident.copyWith(status: newStatus);
        }
      }
    });

    final success =
        await ApiService.updateIncidentStatus(incident.id, newStatus);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Status updated to $newStatus'
              : 'Update queued — will sync when online'),
          backgroundColor: success ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _requestBackup(Incident incident) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Backup'),
        content: const Text(
            'This will send a backup request for additional volunteers/responders at this location.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Backup Request'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final backupIncident = Incident(
        id: 0,
        type: incident.type,
        lat: incident.lat,
        lon: incident.lon,
        severity: (incident.severity + 1).clamp(1, 5),
        description: 'BACKUP REQUESTED: ${incident.description}',
        disasterType: incident.disasterType,
        areaId: incident.areaId,
        status: 'active',
        timestamp: DateTime.now(),
        lastUpdated: DateTime.now(),
        peopleAffected: incident.peopleAffected,
      );
      await ApiService.postIncident(backupIncident);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup request sent'),
            backgroundColor: Colors.green,
          ),
        );
        _loadTasks();
      }
    }
  }

  void _openDirections(Incident incident) async {
    if (_currentPosition == null) return;
    final origin =
        '${_currentPosition!.latitude},${_currentPosition!.longitude}';
    final destination = '${incident.lat},${incident.lon}';
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => SettingsSheet.show(context),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Available (${_availableTasks.length})'),
            Tab(text: 'Active (${_myActiveTasks.length})'),
            Tab(text: 'History (${_completedTasks.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTasks,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAvailableTab(),
                  _buildActiveTab(),
                  _buildHistoryTab(),
                ],
              ),
            ),
    );
  }

  // ── Available Tasks tab (accept/decline) ──
  Widget _buildAvailableTab() {
    if (_availableTasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildPoliceStationGuidanceCard(),
          const SizedBox(height: 18),
          const Center(
            child: Text(
              'No available tasks nearby',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _availableTasks.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _buildPoliceStationGuidanceCard();
        }

        final taskIndex = i - 1;
        final task = _availableTasks[taskIndex];
        final distance = _currentPosition != null
            ? Geolocator.distanceBetween(_currentPosition!.latitude,
                _currentPosition!.longitude, task.lat, task.lon)
            : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _severityBadge(task.severity),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.type.replaceAll('_', ' '),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(task.areaId,
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_formatDistance(distance),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        if (task.peopleAffected != null)
                          Text('${task.peopleAffected} people',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(task.description,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _acceptTask(task),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _declineTask(task),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _openDirections(task),
                      icon: const Icon(Icons.map, color: Colors.teal),
                      tooltip: 'View on Map',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPoliceStationGuidanceCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Volunteer Instructions',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please report to the recommended police station before traveling to the incident location. ',
          ),
          SizedBox(height: 8),
          Text(
            'Tap the map icon on a task to open directions in an external app.',
          ),
        ],
      ),
    );
  }

  // ── Active Tasks tab (status progression + request backup) ──
  Widget _buildActiveTab() {
    if (_myActiveTasks.isEmpty) {
      return const Center(
        child: Text('No active tasks',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _myActiveTasks.length,
      itemBuilder: (ctx, i) {
        final task = _myActiveTasks[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _severityBadge(task.severity),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        task.type.replaceAll('_', ' '),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    _statusChip(task.status),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Location: ${task.areaId}'),
                if (task.description.isNotEmpty)
                  Text(task.description,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                const SizedBox(height: 12),
                const Text('Update Status:',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _progressButton(
                        'En Route', Colors.blue, task, 'in-progress'),
                    _progressButton(
                        'On Scene', Colors.orange, task, 'in-progress'),
                    _progressButton('Resolved', Colors.green, task, 'resolved'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _requestBackup(task),
                        icon: const Icon(Icons.group_add, size: 18),
                        label: const Text('Request Backup'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _openDirections(task),
                      icon: const Icon(Icons.directions, color: Colors.teal),
                      tooltip: 'Get Directions',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _progressButton(
      String label, Color color, Incident task, String newStatus) {
    return ElevatedButton(
      onPressed: () => _progressTask(task, newStatus),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  // ── History tab (completed tasks with timestamps) ──
  Widget _buildHistoryTab() {
    if (_completedTasks.isEmpty) {
      return const Center(
        child: Text('No completed tasks yet',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _completedTasks.length,
      itemBuilder: (ctx, i) {
        final task = _completedTasks[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green[100],
              child: const Icon(Icons.check, color: Colors.green),
            ),
            title: Text(task.type.replaceAll('_', ' ')),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location: ${task.areaId}'),
                Text('Resolved: ${_formatTimestamp(task.lastUpdated)}'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _severityBadge(int severity) {
    Color color;
    String label;
    if (severity >= 4) {
      color = Colors.red;
      label = 'CRITICAL';
    } else if (severity >= 2) {
      color = Colors.orange;
      label = 'HIGH';
    } else {
      color = Colors.green;
      label = 'LOW';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.replaceAll('-', ' ').toUpperCase(),
        style: TextStyle(
            color: Colors.teal[700], fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
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
