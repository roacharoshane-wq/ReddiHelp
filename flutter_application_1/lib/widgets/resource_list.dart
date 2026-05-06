import 'package:flutter/material.dart';
import '../models/resource.dart';

class ResourceList extends StatelessWidget {
  final List<Resource> resources;

  const ResourceList({super.key, required this.resources});

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
                Icon(Icons.inventory, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Resource Inventory',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...resources
                .map((resource) => _buildResourceItem(context, resource)),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceItem(BuildContext context, Resource resource) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getResourceColor(resource.type).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                _getResourceIcon(resource.type),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatResourceName(resource.type),
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      height: 8,
                      width: _getResourceWidth(context, resource),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getResourceColor(resource.type).withOpacity(0.7),
                            _getResourceColor(resource.type),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getResourceColor(resource.type).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${resource.quantity} ${_getResourceUnit(resource.type)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: _getResourceColor(resource.type),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getResourceWidth(BuildContext context, Resource resource) {
    // Calculate percentage based on typical maximum quantities
    const maxQuantities = {
      'water': 1000,
      'food': 500,
      'medical': 200,
      'shelter': 50,
      'rescue_team': 10,
    };

    final maxQuantity = maxQuantities[resource.type] ?? 100;
    final percentage = (resource.quantity / maxQuantity).clamp(0.0, 1.0);

    // Get the available width for the progress bar (approximately 60% of screen width minus padding)
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth =
        screenWidth * 0.4; // Adjust this based on your layout

    return availableWidth * percentage;
  }

  String _getResourceIcon(String type) {
    switch (type) {
      case 'water':
        return '💧';
      case 'food':
        return '🍲';
      case 'medical':
        return '💊';
      case 'shelter':
        return '🏠';
      case 'rescue_team':
        return '🚑';
      default:
        return '📦';
    }
  }

  Color _getResourceColor(String type) {
    switch (type) {
      case 'water':
        return Colors.blue;
      case 'food':
        return Colors.green;
      case 'medical':
        return Colors.red;
      case 'shelter':
        return Colors.orange;
      case 'rescue_team':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getResourceUnit(String type) {
    switch (type) {
      case 'water':
        return 'L';
      case 'food':
        return 'pkg';
      case 'medical':
        return 'kits';
      case 'shelter':
        return 'spaces';
      case 'rescue_team':
        return 'teams';
      default:
        return 'units';
    }
  }

  String _formatResourceName(String type) {
    return type
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

// Alternative: Grid View Version
class ResourceGrid extends StatelessWidget {
  final List<Resource> resources;

  const ResourceGrid({super.key, required this.resources});

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
                Icon(Icons.inventory, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Resource Inventory',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: resources
                  .map((resource) => _buildResourceCard(resource))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceCard(Resource resource) {
    final percentage =
        (resource.quantity / _getMaxQuantity(resource.type)).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: _getResourceColor(resource.type).withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _getResourceColor(resource.type).withOpacity(0.2),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              heightFactor: percentage,
              child: Container(
                decoration: BoxDecoration(
                  color: _getResourceColor(resource.type).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      _getResourceIcon(resource.type),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatResourceName(resource.type),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${resource.quantity}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _getResourceColor(resource.type),
                      ),
                    ),
                    Text(
                      _getResourceUnit(resource.type),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _getMaxQuantity(String type) {
    switch (type) {
      case 'water':
        return 1000;
      case 'food':
        return 500;
      case 'medical':
        return 200;
      case 'shelter':
        return 50;
      case 'rescue_team':
        return 10;
      default:
        return 100;
    }
  }

  String _getResourceIcon(String type) {
    switch (type) {
      case 'water':
        return '💧';
      case 'food':
        return '🍲';
      case 'medical':
        return '💊';
      case 'shelter':
        return '🏠';
      case 'rescue_team':
        return '🚑';
      default:
        return '📦';
    }
  }

  Color _getResourceColor(String type) {
    switch (type) {
      case 'water':
        return Colors.blue;
      case 'food':
        return Colors.green;
      case 'medical':
        return Colors.red;
      case 'shelter':
        return Colors.orange;
      case 'rescue_team':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getResourceUnit(String type) {
    switch (type) {
      case 'water':
        return 'liters';
      case 'food':
        return 'packages';
      case 'medical':
        return 'kits';
      case 'shelter':
        return 'spaces';
      case 'rescue_team':
        return 'teams';
      default:
        return 'units';
    }
  }

  String _formatResourceName(String type) {
    return type
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

// Alternative: Compact Version for Small Spaces
class CompactResourceList extends StatelessWidget {
  final List<Resource> resources;

  const CompactResourceList({super.key, required this.resources});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: resources.map((resource) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getResourceColor(resource.type).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _getResourceColor(resource.type).withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getResourceIcon(resource.type),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(
                '${resource.quantity} ${_getResourceUnit(resource.type)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _getResourceColor(resource.type),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getResourceIcon(String type) {
    switch (type) {
      case 'water':
        return '💧';
      case 'food':
        return '🍲';
      case 'medical':
        return '💊';
      case 'shelter':
        return '🏠';
      case 'rescue_team':
        return '🚑';
      default:
        return '📦';
    }
  }

  Color _getResourceColor(String type) {
    switch (type) {
      case 'water':
        return Colors.blue;
      case 'food':
        return Colors.green;
      case 'medical':
        return Colors.red;
      case 'shelter':
        return Colors.orange;
      case 'rescue_team':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getResourceUnit(String type) {
    switch (type) {
      case 'water':
        return 'L';
      case 'food':
        return 'pkg';
      case 'medical':
        return 'kits';
      case 'shelter':
        return 'spcs';
      case 'rescue_team':
        return 'tms';
      default:
        return '';
    }
  }
}

// Alternative: Expandable Version with Update Controls
class ExpandableResourceList extends StatefulWidget {
  final List<Resource> resources;
  final Function(String type, int quantity, String operation)? onUpdate;

  const ExpandableResourceList({
    super.key,
    required this.resources,
    this.onUpdate,
  });

  @override
  _ExpandableResourceListState createState() => _ExpandableResourceListState();
}

class _ExpandableResourceListState extends State<ExpandableResourceList> {
  bool _isExpanded = false;

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
            InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Row(
                children: [
                  const Icon(Icons.inventory, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    'Resource Inventory',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              ...widget.resources
                  .map((resource) => _buildExpandableResourceItem(resource)),
            ] else ...[
              const SizedBox(height: 12),
              _buildCompactPreview(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactPreview() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.resources.map((resource) {
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getResourceColor(resource.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(_getResourceIcon(resource.type)),
                  const SizedBox(width: 4),
                  Text(
                    '${resource.quantity}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getResourceColor(resource.type),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpandableResourceItem(Resource resource) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getResourceColor(resource.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _getResourceIcon(resource.type),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatResourceName(resource.type),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value:
                          (resource.quantity / _getMaxQuantity(resource.type))
                              .clamp(0.0, 1.0),
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getResourceColor(resource.type),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${resource.quantity}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getResourceColor(resource.type),
                ),
              ),
            ],
          ),
          if (widget.onUpdate != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: Colors.red,
                  onPressed: () => widget.onUpdate!(
                    resource.type,
                    1,
                    'remove',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: Colors.green,
                  onPressed: () => widget.onUpdate!(
                    resource.type,
                    1,
                    'add',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  double _getMaxQuantity(String type) {
    switch (type) {
      case 'water':
        return 1000;
      case 'food':
        return 500;
      case 'medical':
        return 200;
      case 'shelter':
        return 50;
      case 'rescue_team':
        return 10;
      default:
        return 100;
    }
  }

  String _getResourceIcon(String type) {
    switch (type) {
      case 'water':
        return '💧';
      case 'food':
        return '🍲';
      case 'medical':
        return '💊';
      case 'shelter':
        return '🏠';
      case 'rescue_team':
        return '🚑';
      default:
        return '📦';
    }
  }

  Color _getResourceColor(String type) {
    switch (type) {
      case 'water':
        return Colors.blue;
      case 'food':
        return Colors.green;
      case 'medical':
        return Colors.red;
      case 'shelter':
        return Colors.orange;
      case 'rescue_team':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatResourceName(String type) {
    return type
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
