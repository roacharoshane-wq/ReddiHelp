import 'package:flutter/material.dart';
import '../models/incident.dart';

class SimpleCharts extends StatelessWidget {
  final List<Incident> incidents;

  const SimpleCharts({super.key, required this.incidents});

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No incidents to display',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Incidents by Type Chart
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
                const SizedBox(height: 16),
                _buildTypeChart(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Severity Distribution Chart
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
                  'Severity Distribution',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSeverityChart(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChart() {
    final typeCounts = <String, int>{};

    for (var incident in incidents) {
      typeCounts[incident.type] = (typeCounts[incident.type] ?? 0) + 1;
    }

    final totalIncidents = incidents.length;
    final typeNames = {
      'medical': '🚑 Medical',
      'fire': '🔥 Fire',
      'flood': '💧 Flood',
      'trapped': '🚶 Trapped',
      'other': '⚠️ Other',
    };

    return Column(
      children: typeCounts.entries.map((entry) {
        final percentage = (entry.value / totalIncidents) * 100;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  typeNames[entry.key] ?? entry.key,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Container(
                      height: 24,
                      width: percentage * 2, // Scale for visual effect
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getTypeColor(entry.key).withOpacity(0.7),
                            _getTypeColor(entry.key),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 40,
                child: Text(
                  '${entry.value}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeverityChart() {
    final severityCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

    for (var incident in incidents) {
      severityCounts[incident.severity] =
          (severityCounts[incident.severity] ?? 0) + 1;
    }

    final maxCount = severityCounts.values.reduce((a, b) => a > b ? a : b);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [1, 2, 3, 4, 5].map((severity) {
        final count = severityCounts[severity] ?? 0;
        // Explicitly typed as double to avoid num inference error
        final double barHeight =
            maxCount > 0 ? (count / maxCount) * 120.0 : 0.0;

        return Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 120,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    if (barHeight > 0)
                      Container(
                        width: 24,
                        height: barHeight,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              _getSeverityColor(severity).withOpacity(0.8),
                              _getSeverityColor(severity),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                severity.toString(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

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
      default:
        return Colors.grey;
    }
  }

  Color _getSeverityColor(int severity) {
    switch (severity) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// Alternative: Pie Chart Version using CustomPaint
class PieChartWidget extends StatelessWidget {
  final Map<String, int> data;
  final double size;

  const PieChartWidget({
    super.key,
    required this.data,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: size,
        child: const Center(
          child: Text('No data'),
        ),
      );
    }

    final total = data.values.reduce((a, b) => a + b);
    const double startAngle = 0.0;

    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(
        painter: _PieChartPainter(data, total, startAngle),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final Map<String, int> data;
  final int total;
  final double startAngle;

  _PieChartPainter(this.data, this.total, this.startAngle);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    var currentAngle = startAngle;

    for (var entry in data.entries) {
      final sweepAngle = (entry.value / total) * 2 * 3.14159;

      final paint = Paint()
        ..color = _getColorForType(entry.key)
        ..style = PaintingStyle.fill;

      canvas.drawArc(rect, currentAngle, sweepAngle, true, paint);
      currentAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Color _getColorForType(String type) {
    switch (type) {
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'flood':
        return Colors.blue;
      case 'trapped':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

// Alternative: Donut Chart Version
class DonutChartWidget extends StatelessWidget {
  final Map<String, int> data;
  final double size;
  final double holeRadius;

  const DonutChartWidget({
    super.key,
    required this.data,
    this.size = 150,
    this.holeRadius = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: size,
        child: const Center(
          child: Text('No data'),
        ),
      );
    }

    final total = data.values.reduce((a, b) => a + b);
    const double startAngle = 0.0;

    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(
        painter: _DonutChartPainter(data, total, startAngle, holeRadius),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final Map<String, int> data;
  final int total;
  final double startAngle;
  final double holeRadius;

  _DonutChartPainter(this.data, this.total, this.startAngle, this.holeRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    var currentAngle = startAngle;

    for (var entry in data.entries) {
      final sweepAngle = (entry.value / total) * 2 * 3.14159;

      final paint = Paint()
        ..color = _getColorForType(entry.key)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - holeRadius;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentAngle,
        sweepAngle,
        false,
        paint,
      );

      currentAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  Color _getColorForType(String type) {
    switch (type) {
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'flood':
        return Colors.blue;
      case 'trapped':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

// Legend widget for charts
class ChartLegend extends StatelessWidget {
  final Map<String, int> data;

  const ChartLegend({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final typeNames = {
      'medical': 'Medical',
      'fire': 'Fire',
      'flood': 'Flood',
      'trapped': 'Trapped',
      'other': 'Other',
    };

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: data.entries.map((entry) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getColorForType(entry.key),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${typeNames[entry.key] ?? entry.key} (${entry.value})',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        );
      }).toList(),
    );
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.orange;
      case 'flood':
        return Colors.blue;
      case 'trapped':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
