// Feature #3 — Gamified Volunteer Contribution Tracker
// Personal stats, badges, monthly leaderboard, shareable impact card.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../models/incident.dart';
import '../widgets/settings_sheet.dart';

class VolunteerStatsScreen extends StatefulWidget {
  const VolunteerStatsScreen({super.key});

  @override
  State<VolunteerStatsScreen> createState() => _VolunteerStatsScreenState();
}

class _VolunteerStatsScreenState extends State<VolunteerStatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey _shareCardKey = GlobalKey();

  bool _loading = true;

  // Personal stats
  int _tasksCompleted = 0;
  int _activeTasks = 0;
  List<String> _badges = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      // Fetch incidents (same source as My Tasks screen) to count
      // resolved and active tasks directly.
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final userId = auth.user?['id'];
      final allIncidents = await ApiService.getIncidents();
      final resolved = allIncidents
          .where((i) => i.status == 'resolved' && i.assignedTo == userId)
          .toList();
      final active = allIncidents
          .where((i) =>
              (i.status == 'active' || i.status == 'in-progress') &&
              i.assignedTo == userId)
          .toList();

      // Allocate badges from incident history analysis
      final earnedBadges = _computeBadges(resolved, active, allIncidents);

      if (mounted) {
        setState(() {
          _tasksCompleted = resolved.length;
          _activeTasks = active.length;
          _badges = earnedBadges;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Analyse incident data (history + active) and determine which badges
  /// the volunteer has earned.  Each badge has a clear, data-driven rule.
  List<String> _computeBadges(
    List<Incident> completed,
    List<Incident> active,
    List<Incident> all,
  ) {
    final earned = <String>[];

    // 1. First Responder — completed at least 1 task
    if (completed.isNotEmpty) earned.add('First Responder');

    // 2. Seasoned Helper — completed 10+ tasks
    if (completed.length >= 10) earned.add('Seasoned Helper');

    // 3. Veteran Volunteer — completed 50+ tasks
    if (completed.length >= 50) earned.add('Veteran Volunteer');

    // 4. Medical Specialist — resolved a medical emergency
    if (completed.any((i) =>
        i.disasterType.toLowerCase() == 'medical' ||
        i.type.toLowerCase() == 'medical')) {
      earned.add('Medical Specialist');
    }

    // 5. Storm Chaser — resolved a hurricane/storm/flood incident
    if (completed.any((i) {
      final dt = i.disasterType.toLowerCase();
      return dt == 'hurricane' || dt == 'storm' || dt == 'flood';
    })) {
      earned.add('Storm Chaser');
    }

    // 6. Crisis Handler — resolved a severity-5 incident
    if (completed.any((i) => i.severity >= 5)) {
      earned.add('Crisis Handler');
    }

    // 7. Multi-Tasker — has 3+ active tasks at once
    if (active.length >= 3) earned.add('Multi-Tasker');

    // 8. Dedicated Volunteer — completed 25+ tasks
    if (completed.length >= 25) earned.add('Dedicated Volunteer');

    return earned;
  }

  Future<void> _shareImpactCard() async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/volunteer_impact.png');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impact card saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Impact'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => SettingsSheet.show(context),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Stats'),
            Tab(icon: Icon(Icons.emoji_events), text: 'Badges'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(),
                _buildBadgesTab(),
              ],
            ),
    );
  }

  // ── Stats Tab ──
  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Shareable impact card
          RepaintBoundary(
            key: _shareCardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3F51B5), Color(0xFF7C4DFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'VOLUNTEER IMPACT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem('$_tasksCompleted', 'Tasks\nCompleted',
                          Icons.task_alt),
                      _statItem('$_activeTasks', 'Active\nTasks',
                          Icons.assignment_outlined),
                      _statItem('${_badges.length}', 'Badges\nEarned',
                          Icons.emoji_events),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_badges.isNotEmpty) ...[
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: _badges
                          .take(4)
                          .map((b) => Chip(
                                label: Text(b,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _shareImpactCard,
            icon: const Icon(Icons.share),
            label: const Text('Share My Impact'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
          ),
          const SizedBox(height: 24),
          // Detailed stat rows
          _detailRow(Icons.task_alt, 'Tasks Completed', '$_tasksCompleted'),
          _detailRow(
              Icons.assignment_outlined, 'Active Tasks', '$_activeTasks'),
          _detailRow(Icons.emoji_events, 'Badges Earned', '${_badges.length}'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 15)),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.indigo),
          ),
        ],
      ),
    );
  }

  // ── Badges Tab ──
  Widget _buildBadgesTab() {
    final allBadges = [
      {
        'name': 'First Responder',
        'desc': 'Complete your first task',
        'icon': Icons.flash_on,
        'color': Colors.amber,
      },
      {
        'name': 'Seasoned Helper',
        'desc': 'Complete 10 tasks',
        'icon': Icons.stars,
        'color': Colors.orange,
      },
      {
        'name': 'Dedicated Volunteer',
        'desc': 'Complete 25 tasks',
        'icon': Icons.volunteer_activism,
        'color': Colors.teal,
      },
      {
        'name': 'Veteran Volunteer',
        'desc': 'Complete 50 tasks',
        'icon': Icons.military_tech,
        'color': Colors.red,
      },
      {
        'name': 'Medical Specialist',
        'desc': 'Resolve a medical emergency',
        'icon': Icons.local_hospital,
        'color': Colors.blue,
      },
      {
        'name': 'Storm Chaser',
        'desc': 'Resolve a hurricane, storm, or flood',
        'icon': Icons.thunderstorm,
        'color': Colors.indigo,
      },
      {
        'name': 'Crisis Handler',
        'desc': 'Resolve a severity-5 incident',
        'icon': Icons.warning_amber,
        'color': Colors.deepOrange,
      },
      {
        'name': 'Multi-Tasker',
        'desc': 'Have 3+ active tasks at once',
        'icon': Icons.dynamic_feed,
        'color': Colors.purple,
      },
    ];

    // Sort: earned badges first, then unearned
    allBadges.sort((a, b) {
      final aEarned = _badges.contains(a['name']) ? 0 : 1;
      final bEarned = _badges.contains(b['name']) ? 0 : 1;
      return aEarned.compareTo(bEarned);
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: allBadges.length,
        itemBuilder: (ctx, i) {
          final badge = allBadges[i];
          final earned = _badges.contains(badge['name']);
          final badgeColor = badge['color'] as MaterialColor;
          return Card(
            elevation: earned ? 6 : 1,
            shadowColor: earned ? badgeColor.withValues(alpha: 0.4) : null,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: earned
                    ? LinearGradient(
                        colors: [
                          badgeColor.withValues(alpha: 0.15),
                          badgeColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                border: earned
                    ? Border.all(color: badgeColor, width: 2)
                    : Border.all(color: Colors.grey.shade300, width: 1),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: earned
                          ? badgeColor.withValues(alpha: 0.2)
                          : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      badge['icon'] as IconData,
                      size: 32,
                      color: earned ? badgeColor : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    badge['name'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: earned ? badgeColor.shade700 : Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge['desc'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        color: earned ? Colors.grey[700] : Colors.grey[500]),
                  ),
                  if (earned) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: badgeColor, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Earned',
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
