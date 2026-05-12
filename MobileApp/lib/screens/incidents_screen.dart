import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/incident.dart';
import '../models/resource.dart';
import '../models/stats.dart';
import '../widgets/stats_cards.dart';
import '../widgets/resource_list.dart';
import '../widgets/simple_charts.dart';
import '../widgets/incident_table.dart';
import 'dart:async';

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  _IncidentsScreenState createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  List<Incident> _incidents = [];
  List<Resource> _resources = [];
  Stats? _stats;
  String _areaId = ' ';
  Map<String, dynamic>? _areaAnalysis;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 30 seconds
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final incidents = await ApiService.getIncidents();
      final resources = await ApiService.getResources();
      final stats = await ApiService.getStats();
      setState(() {
        _incidents = incidents;
        _resources = resources;
        _stats = stats;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  Future<void> _analyzeArea() async {
    try {
      final severity = await ApiService.getAreaSeverity(_areaId);
      final estimate = await ApiService.getAreaResourceEstimate(_areaId);
      setState(() {
        _areaAnalysis = {
          'severity': severity,
          'estimate': estimate,
        };
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Area analysis failed: $e')),
      );
    }
  }

  Future<void> _updateIncidentStatus(int id, String status) async {
    try {
      await ApiService.updateIncidentStatus(id, status);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $e')),
      );
    }
  }

  Future<void> _deleteIncident(int id) async {
    try {
      await ApiService.deleteIncident(id);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _stats == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatsCards(stats: _stats!),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SimpleCharts(incidents: _incidents),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ResourceList(resources: _resources),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Area Analysis Card (improved)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Parish Analysis',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: const InputDecoration(
                                    labelText: 'Parish Name',
                                    hintText:
                                        'eg. Kingston, Portland, Clarendon',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) => _areaId = value,
                                  controller:
                                      TextEditingController(text: _areaId),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: _analyzeArea,
                                child: const Text('Analyze'),
                              ),
                            ],
                          ),
                          if (_areaAnalysis != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning,
                                          color: Colors.orange),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Severity Score: ${_areaAnalysis!['severity']['severityScore'].toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.list,
                                          color: Colors.blue),
                                      const SizedBox(width: 8),
                                      Text(
                                          'Incident Count: ${_areaAnalysis!['severity']['incidentCount']}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('Required Resources:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            // Resource grid similar to HTML
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              childAspectRatio: 1.2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              children: (_areaAnalysis!['estimate']['needed']
                                      as Map<String, dynamic>)
                                  .entries
                                  .where((e) => e.value > 0)
                                  .map((e) {
                                return _buildResourceCard(e.key, e.value);
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  IncidentTable(
                    incidents: _incidents,
                    onStatusChange: _updateIncidentStatus,
                    onDelete: _deleteIncident,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildResourceCard(String type, int quantity) {
    // Map resource types to icons and colors
    final Map<String, IconData> iconMap = {
      'water': Icons.water_drop,
      'food': Icons.restaurant,
      'medical': Icons.medical_services,
      'shelter': Icons.home,
      'rescue_team': Icons.emergency,
    };
    final Map<String, Color> colorMap = {
      'water': Colors.blue,
      'food': Colors.green,
      'medical': Colors.red,
      'shelter': Colors.orange,
      'rescue_team': Colors.purple,
    };
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconMap[type] ?? Icons.inventory,
                color: colorMap[type] ?? Colors.grey, size: 24),
            const SizedBox(height: 4),
            Text(
              type.replaceAll('_', ' '),
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            Text(
              quantity.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colorMap[type] ?? Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
