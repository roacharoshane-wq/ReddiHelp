import 'package:flutter/material.dart';
import '../models/stats.dart';

class StatsCards extends StatelessWidget {
  final Stats stats;

  const StatsCards({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildStatCard(
          context,
          title: 'Total Incidents',
          value: stats.totalIncidents.toString(),
          icon: Icons.warning_amber_rounded,
          color: Colors.blue,
        ),
        _buildStatCard(
          context,
          title: 'Active',
          value: stats.activeIncidents.toString(),
          icon: Icons.autorenew,
          color: Colors.orange,
        ),
        _buildStatCard(
          context,
          title: 'Resolved',
          value: stats.resolvedIncidents.toString(),
          icon: Icons.check_circle,
          color: Colors.green,
        ),
        _buildStatCard(
          context,
          title: 'Critical',
          value: (stats.bySeverity['critical'] ?? 0).toString(),
          icon: Icons.crisis_alert,
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Alternative version with more detailed stats (optional)
class DetailedStatsCards extends StatelessWidget {
  final Stats stats;

  const DetailedStatsCards({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // First row - main stats
        Row(
          children: [
            Expanded(
              child: _buildSimpleStatCard(
                context,
                title: 'Total',
                value: stats.totalIncidents.toString(),
                icon: Icons.warning,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSimpleStatCard(
                context,
                title: 'Active',
                value: stats.activeIncidents.toString(),
                icon: Icons.autorenew,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Second row - more stats
        Row(
          children: [
            Expanded(
              child: _buildSimpleStatCard(
                context,
                title: 'Resolved',
                value: stats.resolvedIncidents.toString(),
                icon: Icons.check_circle,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSimpleStatCard(
                context,
                title: 'Critical',
                value: (stats.bySeverity['critical'] ?? 0).toString(),
                icon: Icons.warning_amber,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Severity breakdown
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Severity Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSeverityBar(
                  'Critical (4-5)',
                  stats.bySeverity['critical'] ?? 0,
                  Colors.red,
                ),
                const SizedBox(height: 8),
                _buildSeverityBar(
                  'Moderate (2-3)',
                  stats.bySeverity['moderate'] ?? 0,
                  Colors.orange,
                ),
                const SizedBox(height: 8),
                _buildSeverityBar(
                  'Low (1)',
                  stats.bySeverity['low'] ?? 0,
                  Colors.green,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Incident types breakdown
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incidents by Type',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...stats.byType.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _getTypeIcon(entry.key),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.key[0].toUpperCase() + entry.key.substring(1),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            entry.value.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityBar(String label, int count, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: 8,
                width: count > 0
                    ? (count / 10) * 100
                    : 0, // Assuming max 10 for demo
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          count.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _getTypeIcon(String type) {
    IconData iconData;
    Color color;

    switch (type) {
      case 'medical':
        iconData = Icons.local_hospital;
        color = Colors.red;
        break;
      case 'fire':
        iconData = Icons.local_fire_department;
        color = Colors.orange;
        break;
      case 'flood':
        iconData = Icons.water_drop;
        color = Colors.blue;
        break;
      case 'trapped':
        iconData = Icons.emergency;
        color = Colors.purple;
        break;
      default:
        iconData = Icons.warning;
        color = Colors.grey;
    }

    return Icon(iconData, color: color, size: 18);
  }
}
