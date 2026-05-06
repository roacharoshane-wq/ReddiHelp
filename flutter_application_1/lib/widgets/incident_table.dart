import 'package:flutter/material.dart';
import '../models/incident.dart';

class IncidentTable extends StatefulWidget {
  final List<Incident> incidents;
  final Function(int id, String status)? onStatusChange;
  final Function(int id)? onDelete;

  const IncidentTable({
    super.key,
    required this.incidents,
    this.onStatusChange,
    this.onDelete,
  });

  @override
  _IncidentTableState createState() => _IncidentTableState();
}

class _IncidentTableState extends State<IncidentTable> {
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  String _searchQuery = '';
  bool _sortAscending = true;
  int _sortColumnIndex = 6; // Default sort by timestamp (descending)

  @override
  Widget build(BuildContext context) {
    final filteredIncidents = _filterIncidents();
    final sortedIncidents = _sortIncidents(filteredIncidents);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and filters
            Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'All Incidents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Search field
                Container(
                  width: 200,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Filter controls
            Row(
              children: [
                Container(
                  width: 150,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _typeFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Types'),
                        ),
                        ..._getIncidentTypes().map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Text(_getTypeIcon(type)),
                                const SizedBox(width: 4),
                                Text(_formatTypeName(type)),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _typeFilter = value!;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 150,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down),
                      items: const [
                        DropdownMenuItem(
                            value: 'all', child: Text('All Status')),
                        DropdownMenuItem(
                            value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                            value: 'resolved', child: Text('Resolved')),
                        DropdownMenuItem(
                            value: 'in-progress', child: Text('In Progress')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _statusFilter = value!;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Clear all button (test only)
                if (widget.onDelete != null)
                  ElevatedButton.icon(
                    onPressed: _showClearAllConfirmation,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear All (Test)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Table
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 64,
                    ),
                    child: DataTable(
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      columnSpacing: 20,
                      headingRowColor: WidgetStateProperty.all(
                        Colors.grey[100],
                      ),
                      columns: [
                        const DataColumn(
                          label: Text('ID',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const DataColumn(
                          label: Text('Type',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: const Text('Severity',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onSort: (columnIndex, ascending) {
                            setState(() {
                              _sortColumnIndex = columnIndex;
                              _sortAscending = ascending;
                            });
                          },
                        ),
                        const DataColumn(
                          label: Text('Location',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const DataColumn(
                          label: Text('Area',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        DataColumn(
                          label: const Text('Status',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onSort: (columnIndex, ascending) {
                            setState(() {
                              _sortColumnIndex = columnIndex;
                              _sortAscending = ascending;
                            });
                          },
                        ),
                        DataColumn(
                          label: const Text('Time',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          onSort: (columnIndex, ascending) {
                            setState(() {
                              _sortColumnIndex = columnIndex;
                              _sortAscending = ascending;
                            });
                          },
                        ),
                        const DataColumn(
                          label: Text('Actions',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                      rows: sortedIncidents.isEmpty
                          ? [
                              DataRow(cells: [
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                                DataCell(Container()),
                              ])
                            ]
                          : sortedIncidents.map((incident) {
                              return DataRow(
                                cells: [
                                  DataCell(Text('#${incident.id}')),
                                  DataCell(
                                    Row(
                                      children: [
                                        Text(_getTypeIcon(incident.type)),
                                        const SizedBox(width: 4),
                                        Text(_formatTypeName(incident.type)),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            _getSeverityColor(incident.severity)
                                                .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${incident.severity}/5',
                                        style: TextStyle(
                                          color: _getSeverityColor(
                                              incident.severity),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                        '${incident.lat.toStringAsFixed(4)}, ${incident.lon.toStringAsFixed(4)}'),
                                  ),
                                  DataCell(Text(incident.areaId)),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(incident.status)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        incident.status.toUpperCase(),
                                        style: TextStyle(
                                          color:
                                              _getStatusColor(incident.status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(_formatDate(incident.timestamp)),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Status dropdown
                                        Container(
                                          width: 100,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: incident.status,
                                              isExpanded: true,
                                              icon: const Icon(
                                                  Icons.arrow_drop_down,
                                                  size: 18),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 'active',
                                                  child: Text('Active',
                                                      style: TextStyle(
                                                          fontSize: 12)),
                                                ),
                                                DropdownMenuItem(
                                                  value: 'in-progress',
                                                  child: Text('In Progress',
                                                      style: TextStyle(
                                                          fontSize: 12)),
                                                ),
                                                DropdownMenuItem(
                                                  value: 'resolved',
                                                  child: Text('Resolved',
                                                      style: TextStyle(
                                                          fontSize: 12)),
                                                ),
                                              ],
                                              onChanged:
                                                  widget.onStatusChange != null
                                                      ? (value) {
                                                          widget.onStatusChange!(
                                                              incident.id,
                                                              value!);
                                                        }
                                                      : null,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Delete button
                                        if (widget.onDelete != null)
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red, size: 18),
                                            onPressed: () =>
                                                _showDeleteConfirmation(
                                                    incident.id),
                                            tooltip: 'Delete',
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                    ),
                  ),
                ),
              ),
            ),

            // Show message when no incidents found
            if (sortedIncidents.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'No incidents found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),

            // Footer with count
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Text(
                    'Showing ${sortedIncidents.length} of ${widget.incidents.length} incidents',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Incident> _filterIncidents() {
    return widget.incidents.where((incident) {
      // Type filter
      if (_typeFilter != 'all' && incident.type != _typeFilter) {
        return false;
      }

      // Status filter
      if (_statusFilter != 'all' && incident.status != _statusFilter) {
        return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final searchString =
            '${incident.id} ${incident.type} ${incident.areaId} ${incident.description}'
                .toLowerCase();
        if (!searchString.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<Incident> _sortIncidents(List<Incident> incidents) {
    if (_sortColumnIndex == -1) return incidents;

    incidents.sort((a, b) {
      int comparison;

      switch (_sortColumnIndex) {
        case 0: // ID
          comparison = a.id.compareTo(b.id);
          break;
        case 1: // Type
          comparison = a.type.compareTo(b.type);
          break;
        case 2: // Severity
          comparison = a.severity.compareTo(b.severity);
          break;
        case 4: // Area
          comparison = a.areaId.compareTo(b.areaId);
          break;
        case 5: // Status
          comparison = a.status.compareTo(b.status);
          break;
        case 6: // Time
          comparison = a.timestamp.compareTo(b.timestamp);
          break;
        default:
          comparison = 0;
      }

      return _sortAscending ? comparison : -comparison;
    });

    return incidents;
  }

  void _showDeleteConfirmation(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Incident'),
        content: Text('Are you sure you want to delete incident #$id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete!(id);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showClearAllConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Incidents'),
        content: const Text(
          'Delete ALL incidents? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              for (var incident in widget.incidents) {
                widget.onDelete!(incident.id);
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  List<String> _getIncidentTypes() {
    return widget.incidents.map((inc) => inc.type).toSet().toList();
  }

  String _getTypeIcon(String type) {
    switch (type) {
      case 'medical':
        return '🚑';
      case 'fire':
        return '🔥';
      case 'flood':
        return '💧';
      case 'trapped':
        return '🚶';
      default:
        return '⚠️';
    }
  }

  String _formatTypeName(String type) {
    return type[0].toUpperCase() + type.substring(1);
  }

  Color _getSeverityColor(int severity) {
    if (severity >= 4) return Colors.red;
    if (severity >= 2) return Colors.orange;
    return Colors.green;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'in-progress':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

// Alternative: Simple version without filtering and sorting
class SimpleIncidentTable extends StatelessWidget {
  final List<Incident> incidents;
  final Function(int id, String status)? onStatusChange;
  final Function(int id)? onDelete;

  const SimpleIncidentTable({
    super.key,
    required this.incidents,
    this.onStatusChange,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.list_alt, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Recent Incidents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: incidents.length > 5 ? 5 : incidents.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final incident = incidents[index];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          _getSeverityColor(incident.severity).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _getTypeIcon(incident.type),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  title: Text(
                    '${_formatTypeName(incident.type)} - ${incident.areaId}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Severity: ${incident.severity}/5 • ${_formatDate(incident.timestamp)}',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(incident.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      incident.status.toUpperCase(),
                      style: TextStyle(
                        color: _getStatusColor(incident.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (incidents.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      // Navigate to full table view
                    },
                    child: Text('View All ${incidents.length} Incidents'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getTypeIcon(String type) {
    switch (type) {
      case 'medical':
        return '🚑';
      case 'fire':
        return '🔥';
      case 'flood':
        return '💧';
      case 'trapped':
        return '🚶';
      default:
        return '⚠️';
    }
  }

  String _formatTypeName(String type) {
    return type[0].toUpperCase() + type.substring(1);
  }

  Color _getSeverityColor(int severity) {
    if (severity >= 4) return Colors.red;
    if (severity >= 2) return Colors.orange;
    return Colors.green;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'in-progress':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
