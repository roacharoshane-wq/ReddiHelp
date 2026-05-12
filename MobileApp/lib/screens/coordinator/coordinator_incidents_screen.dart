import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../models/incident.dart';

class CoordinatorIncidentsScreen extends StatefulWidget {
  const CoordinatorIncidentsScreen({super.key});

  @override
  State<CoordinatorIncidentsScreen> createState() =>
      _CoordinatorIncidentsScreenState();
}

class _CoordinatorIncidentsScreenState
    extends State<CoordinatorIncidentsScreen> {
  List<Incident> _incidents = [];
  bool _loading = true;
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  String _searchQuery = '';
  String _sortBy = 'default';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadIncidents();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadIncidents());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIncidents() async {
    try {
      final incidents = await ApiService.getIncidents();
      if (!mounted) return;
      setState(() {
        _incidents = incidents;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Incident> get _filteredIncidents {
    var list = List<Incident>.from(_incidents);

    if (_statusFilter != 'all') {
      list = list.where((i) => i.status == _statusFilter).toList();
    }
    if (_typeFilter != 'all') {
      list = list.where((i) => i.type == _typeFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((i) =>
              i.description
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              i.areaId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              '#${i.id}'.contains(_searchQuery))
          .toList();
    }

    switch (_sortBy) {
      case 'severity':
        list.sort((a, b) => b.severity.compareTo(a.severity));
        break;
      case 'time':
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      default:
        // Default: unassigned first, then severity, then time
        list.sort((a, b) {
          final aUnassigned = a.assignedTo == null ? 0 : 1;
          final bUnassigned = b.assignedTo == null ? 0 : 1;
          if (aUnassigned != bUnassigned)
            return aUnassigned.compareTo(bUnassigned);
          if (a.severity != b.severity) return b.severity.compareTo(a.severity);
          return b.timestamp.compareTo(a.timestamp);
        });
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredIncidents;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Incident Queue'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${filtered.length}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadIncidents,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBar(isDark),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No incidents match filters',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadIncidents,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) =>
                                _buildIncidentRow(filtered[i], isDark),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF333333) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by ID, area, or description...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
            ),
          ),
          const SizedBox(height: 8),
          // Filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all', _statusFilter,
                    (v) => setState(() => _statusFilter = v)),
                _buildFilterChip('Active', 'active', _statusFilter,
                    (v) => setState(() => _statusFilter = v)),
                _buildFilterChip('In Progress', 'in-progress', _statusFilter,
                    (v) => setState(() => _statusFilter = v)),
                _buildFilterChip('Resolved', 'resolved', _statusFilter,
                    (v) => setState(() => _statusFilter = v)),
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: Colors.grey[400]),
                const SizedBox(width: 8),
                _buildSortChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label, String value, String current, ValueChanged<String> onTap) {
    final isSelected = current == value;
    const teal = Color(0xFF0D9488);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (_) => onTap(value),
        selectedColor: teal.withOpacity(0.15),
        checkmarkColor: teal,
        labelStyle: TextStyle(
          color: isSelected ? teal : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildSortChip() {
    return PopupMenuButton<String>(
      onSelected: (v) => setState(() => _sortBy = v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'default', child: Text('Default')),
        const PopupMenuItem(value: 'severity', child: Text('Severity')),
        const PopupMenuItem(value: 'time', child: Text('Most Recent')),
      ],
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(
          _sortBy == 'default'
              ? 'Sort'
              : _sortBy[0].toUpperCase() + _sortBy.substring(1),
          style: const TextStyle(fontSize: 12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildIncidentRow(Incident inc, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Severity bar (colored left border like backend)
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: _severityColor(inc.severity),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                onTap: () => _showIncidentDetail(inc),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_typeEmoji(inc.type),
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${inc.id}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      inc.areaId,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  inc.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildStatusBadge(inc.status),
                              const SizedBox(height: 4),
                              Text(_formatTimeAgo(inc.timestamp),
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey[500])),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildSeverityIndicator(inc.severity),
                          const Spacer(),
                          if (inc.peopleAffected != null &&
                              inc.peopleAffected! > 0)
                            Row(
                              children: [
                                Icon(Icons.people,
                                    size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text('${inc.peopleAffected}',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500])),
                              ],
                            ),
                          const SizedBox(width: 12),
                          Icon(
                            inc.assignedTo != null
                                ? Icons.person
                                : Icons.person_add_alt_1,
                            size: 14,
                            color: inc.assignedTo != null
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            inc.responderName ?? 'Unassigned',
                            style: TextStyle(
                              fontSize: 11,
                              color: inc.assignedTo != null
                                  ? Colors.grey[600]
                                  : const Color(0xFFEF4444),
                              fontWeight: inc.assignedTo == null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityIndicator(int severity) {
    final labels = ['Low', 'Medium', 'High', 'Critical', 'Catastrophic'];
    final label =
        severity >= 1 && severity <= 5 ? labels[severity - 1] : 'Sev $severity';

    return Row(
      children: [
        ...List.generate(5, (i) {
          return Container(
            width: 16,
            height: 4,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i < severity
                  ? _severityColor(severity)
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: _severityColor(severity),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _showIncidentDetail(Incident inc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _buildIncidentDetailSheet(inc, controller),
      ),
    );
  }

  Widget _buildIncidentDetailSheet(Incident inc, ScrollController controller) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: ListView(
        controller: controller,
        children: [
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
          // Header
          Row(
            children: [
              Text(_typeEmoji(inc.type), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${inc.id} ${inc.type[0].toUpperCase()}${inc.type.substring(1)}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (inc.referenceNumber != null)
                      Text(inc.referenceNumber!,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
              ),
              _buildStatusBadge(inc.status),
            ],
          ),
          const SizedBox(height: 16),
          _buildSeverityIndicator(inc.severity),
          const Divider(height: 24),

          // Overview
          _detailRow(Icons.description, 'Description', inc.description),
          _detailRow(Icons.location_on, 'Area', inc.areaId),
          _detailRow(Icons.my_location, 'Coordinates',
              '${inc.lat.toStringAsFixed(4)}, ${inc.lon.toStringAsFixed(4)}'),
          if (inc.peopleAffected != null)
            _detailRow(
                Icons.people, 'People Affected', '${inc.peopleAffected}'),
          _detailRow(
              Icons.access_time, 'Reported', _formatTimeAgo(inc.timestamp)),

          const Divider(height: 24),

          // Contacts
          _detailRow(
            Icons.person_outline,
            'Victim',
            inc.victimName ?? 'Unknown',
            subtitle: inc.victimPhone,
          ),
          _detailRow(
            Icons.support_agent,
            'Responder',
            inc.responderName ?? 'Unassigned',
            subtitle: inc.responderPhone,
          ),

          const SizedBox(height: 20),

          // Actions
          Row(
            children: [
              if (inc.status != 'resolved') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _assignVolunteer(inc),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Assign'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatusTransitionButton(inc),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500)),
                Text(value, style: const TextStyle(fontSize: 14)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTransitionButton(Incident inc) {
    String nextStatus;
    String label;
    Color color;

    switch (inc.status) {
      case 'submitted':
        nextStatus = 'active';
        label = 'Activate';
        color = const Color(0xFF3B82F6);
        break;
      case 'active':
        nextStatus = 'in-progress';
        label = 'In Progress';
        color = const Color(0xFFF97316);
        break;
      case 'in-progress':
        nextStatus = 'resolved';
        label = 'Resolve';
        color = const Color(0xFF22C55E);
        break;
      default:
        nextStatus = 'active';
        label = 'Reopen';
        color = const Color(0xFF3B82F6);
    }

    return OutlinedButton.icon(
      onPressed: () async {
        Navigator.pop(context);
        await ApiService.transitionIncidentStatus(inc.id, nextStatus);
        _loadIncidents();
      },
      icon: Icon(Icons.arrow_forward, size: 18, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
    );
  }

  Future<void> _assignVolunteer(Incident inc) async {
    final volunteers = await ApiService.getVolunteers();
    if (!mounted) return;

    if (volunteers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No volunteers available')),
      );
      return;
    }

    Navigator.pop(context); // Close detail sheet

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
              const Text('Assign Responder',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('#${inc.id} — ${inc.areaId}',
                  style: TextStyle(color: Colors.grey[600])),
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: volunteers.length,
                  itemBuilder: (_, i) {
                    final v = volunteers[i];
                    final isAvailable = v['availability'] == 'available';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isAvailable
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFF97316),
                          child: Text(
                            (v['username'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(v['username'] ?? 'Unknown'),
                        subtitle: Text(
                          '${v['role'] ?? 'volunteer'} • ${v['availability'] ?? 'unknown'}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final success = await ApiService.assignIncident(
                              inc.id, v['id'] as int);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success
                                    ? 'Assigned to ${v['username']}'
                                    : 'Assignment failed'),
                                backgroundColor:
                                    success ? Colors.green : Colors.red,
                              ),
                            );
                            _loadIncidents();
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

  Widget _buildStatusBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'active':
        bg = const Color(0xFF3B82F6).withOpacity(0.12);
        fg = const Color(0xFF3B82F6);
        break;
      case 'in-progress':
        bg = const Color(0xFFF97316).withOpacity(0.12);
        fg = const Color(0xFFF97316);
        break;
      case 'resolved':
        bg = const Color(0xFF22C55E).withOpacity(0.12);
        fg = const Color(0xFF22C55E);
        break;
      default:
        bg = Colors.grey.withOpacity(0.12);
        fg = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _severityColor(int severity) {
    if (severity >= 5) return const Color(0xFF991B1B);
    if (severity >= 4) return const Color(0xFFEF4444);
    if (severity >= 3) return const Color(0xFFF97316);
    if (severity >= 2) return const Color(0xFFEAB308);
    return const Color(0xFF22C55E);
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'medical':
      case 'medical_emergency':
        return '🏥';
      case 'fire':
        return '🔥';
      case 'flood':
        return '🌊';
      case 'trapped':
        return '⚠️';
      case 'supplies':
      case 'need_supplies':
        return '📦';
      case 'shelter':
      case 'need_shelter':
        return '🏠';
      default:
        return '⚠️';
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
