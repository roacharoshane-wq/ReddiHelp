import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';

class CoordinatorVolunteersScreen extends StatefulWidget {
  const CoordinatorVolunteersScreen({super.key});

  @override
  State<CoordinatorVolunteersScreen> createState() =>
      _CoordinatorVolunteersScreenState();
}

class _CoordinatorVolunteersScreenState
    extends State<CoordinatorVolunteersScreen> {
  List<Map<String, dynamic>> _volunteers = [];
  bool _loading = true;
  String _statusFilter = 'all';
  String _searchQuery = '';
  bool _gridView = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadVolunteers();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadVolunteers());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVolunteers() async {
    try {
      final vols = await ApiService.getVolunteers();
      if (!mounted) return;
      setState(() {
        _volunteers = vols;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_volunteers);

    if (_statusFilter != 'all') {
      list = list.where((v) => v['availability'] == _statusFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((v) =>
              (v['username'] ?? '').toString().toLowerCase().contains(q) ||
              (v['phone'] ?? '').toString().toLowerCase().contains(q) ||
              (v['role'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    return list;
  }

  int get _totalCount => _volunteers.length;
  int get _availableCount =>
      _volunteers.where((v) => v['availability'] == 'available').length;
  int get _onTaskCount =>
      _volunteers.where((v) => v['availability'] == 'on_task').length;
  int get _offlineCount =>
      _volunteers.where((v) => v['availability'] == 'offline').length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Volunteers'),
        actions: [
          IconButton(
            icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVolunteers,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsHeader(isDark),
                _buildFilters(isDark),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No volunteers found',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadVolunteers,
                          child: _gridView
                              ? _buildGridView(filtered, isDark)
                              : _buildListView(filtered, isDark),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildMiniStat(
              'Total', _totalCount.toString(), const Color(0xFF3B82F6), isDark),
          const SizedBox(width: 10),
          _buildMiniStat('Available', _availableCount.toString(),
              const Color(0xFF22C55E), isDark),
          const SizedBox(width: 10),
          _buildMiniStat('On Task', _onTaskCount.toString(),
              const Color(0xFFF97316), isDark),
          const SizedBox(width: 10),
          _buildMiniStat(
              'Offline', _offlineCount.toString(), Colors.grey, isDark),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search volunteers...',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', 'all'),
                _filterChip('Available', 'available'),
                _filterChip('On Task', 'on_task'),
                _filterChip('Offline', 'offline'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    const teal = Color(0xFF0D9488);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isSelected,
        onSelected: (_) => setState(() => _statusFilter = value),
        selectedColor: teal.withOpacity(0.15),
        checkmarkColor: teal,
        labelStyle: TextStyle(
          color: isSelected ? teal : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> vols, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: vols.length,
      itemBuilder: (ctx, i) => _buildVolunteerListItem(vols[i], isDark),
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> vols, bool isDark) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: vols.length,
      itemBuilder: (ctx, i) => _buildVolunteerGridCard(vols[i], isDark),
    );
  }

  Widget _buildVolunteerListItem(Map<String, dynamic> v, bool isDark) {
    final name = v['username'] ?? 'Unknown';
    final role = v['role'] ?? 'volunteer';
    final availability = v['availability'] ?? 'offline';
    final activeTasks = v['activeTaskCount'] ?? 0;
    final completedTasks = v['completedTaskCount'] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF0D9488).withOpacity(0.15),
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF0D9488),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _availabilityColor(availability),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_roleEmoji(role)} $role',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Row(
              children: [
                Text('Active: $activeTasks',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(width: 8),
                Text('Done: $completedTasks',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
        trailing: _buildAvailabilityBadge(availability),
        onTap: () => _showVolunteerDetail(v),
      ),
    );
  }

  Widget _buildVolunteerGridCard(Map<String, dynamic> v, bool isDark) {
    final name = v['username'] ?? 'Unknown';
    final role = v['role'] ?? 'volunteer';
    final availability = v['availability'] ?? 'offline';
    final activeTasks = v['activeTaskCount'] ?? 0;

    return GestureDetector(
      onTap: () => _showVolunteerDetail(v),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF0D9488).withOpacity(0.15),
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _availabilityColor(availability),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${_roleEmoji(role)} $role',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvailabilityBadge(availability),
                  if (activeTasks > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$activeTasks',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF3B82F6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityBadge(String availability) {
    final color = _availabilityColor(availability);
    final label = availability.replaceAll('_', ' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label.toUpperCase(),
        style:
            TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showVolunteerDetail(Map<String, dynamic> v) {
    final name = v['username'] ?? 'Unknown';
    final role = v['role'] ?? 'volunteer';
    final availability = v['availability'] ?? 'offline';
    final phone = v['phone'] ?? '';
    final skills =
        v['skills'] is List ? (v['skills'] as List).cast<String>() : <String>[];
    final activeTasks = v['activeTaskCount'] ?? 0;
    final completedTasks = v['completedTaskCount'] ?? 0;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFF0D9488).withOpacity(0.15),
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF0D9488),
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('${_roleEmoji(role)} $role',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            _buildAvailabilityBadge(availability),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statColumn(
                    'Active', activeTasks.toString(), const Color(0xFFF97316)),
                const SizedBox(width: 32),
                _statColumn('Completed', completedTasks.toString(),
                    const Color(0xFF22C55E)),
              ],
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(phone, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ],
            if (skills.isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Skills',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: skills
                    .map((s) => Chip(
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Color _availabilityColor(String availability) {
    switch (availability) {
      case 'available':
        return const Color(0xFF22C55E);
      case 'on_task':
        return const Color(0xFF3B82F6);
      case 'busy':
        return const Color(0xFFF97316);
      default:
        return Colors.grey;
    }
  }

  String _roleEmoji(String role) {
    switch (role) {
      case 'medical_professional':
        return '🏥';
      case 'fire_rescue':
        return '🚒';
      case 'search_rescue':
        return '🔍';
      case 'logistics':
        return '📦';
      default:
        return '🤝';
    }
  }
}
