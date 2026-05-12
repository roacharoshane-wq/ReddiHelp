import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';

class CoordinatorBroadcastsScreen extends StatefulWidget {
  const CoordinatorBroadcastsScreen({super.key});

  @override
  State<CoordinatorBroadcastsScreen> createState() =>
      _CoordinatorBroadcastsScreenState();
}

class _CoordinatorBroadcastsScreenState
    extends State<CoordinatorBroadcastsScreen> {
  List<Map<String, dynamic>> _broadcasts = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadBroadcasts();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadBroadcasts());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBroadcasts() async {
    try {
      final data = await ApiService.getBroadcasts();
      if (!mounted) return;
      setState(() {
        _broadcasts = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _criticalCount =>
      _broadcasts.where((b) => b['severity'] == 'critical').length;
  int get _last24hCount {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return _broadcasts.where((b) {
      final created = DateTime.tryParse(b['created_at']?.toString() ?? '');
      return created != null && created.isAfter(cutoff);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcasts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadBroadcasts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showComposeBroadcast,
        icon: const Icon(Icons.campaign),
        label: const Text('New Broadcast'),
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStatsBar(isDark),
                Expanded(
                  child: _broadcasts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.campaign_outlined,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('No broadcasts yet',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadBroadcasts,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _broadcasts.length,
                            itemBuilder: (ctx, i) =>
                                _buildBroadcastCard(_broadcasts[i], isDark),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatBadge('Total', _broadcasts.length.toString(),
              const Color(0xFF3B82F6), isDark),
          const SizedBox(width: 10),
          _buildStatBadge('Critical', _criticalCount.toString(),
              const Color(0xFFEF4444), isDark),
          const SizedBox(width: 10),
          _buildStatBadge('Last 24h', _last24hCount.toString(),
              const Color(0xFFF97316), isDark),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildBroadcastCard(Map<String, dynamic> b, bool isDark) {
    final title = b['title'] ?? 'Broadcast';
    final message = b['message'] ?? '';
    final severity = b['severity'] ?? 'info';
    final createdAt = DateTime.tryParse(b['created_at']?.toString() ?? '');
    final recipientCount = b['recipientCount'] ?? b['recipient_count'] ?? 0;
    final deliveredCount = b['deliveredCount'] ?? b['delivered_count'] ?? 0;

    Color severityColor;
    IconData severityIcon;
    switch (severity) {
      case 'critical':
        severityColor = const Color(0xFFDC2626);
        severityIcon = Icons.error;
        break;
      case 'warning':
        severityColor = const Color(0xFFF59E0B);
        severityIcon = Icons.warning;
        break;
      default:
        severityColor = const Color(0xFF3B82F6);
        severityIcon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: severityColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(severityIcon, color: severityColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: severityColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            severity.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: severityColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600], height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '$recipientCount recipients',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.check_circle_outline,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '$deliveredCount delivered',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        const Spacer(),
                        if (createdAt != null)
                          Text(
                            _formatTimeAgo(createdAt),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComposeBroadcast() {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    String severity = 'info';
    final targetAreaController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const Text('New Broadcast',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Broadcast title...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Broadcast message...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Severity',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _severityOption('info', 'Info', const Color(0xFF3B82F6),
                        severity, (v) => setSheetState(() => severity = v)),
                    const SizedBox(width: 8),
                    _severityOption(
                        'warning',
                        'Warning',
                        const Color(0xFFF59E0B),
                        severity,
                        (v) => setSheetState(() => severity = v)),
                    const SizedBox(width: 8),
                    _severityOption(
                        'critical',
                        'Critical',
                        const Color(0xFFDC2626),
                        severity,
                        (v) => setSheetState(() => severity = v)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetAreaController,
                  decoration: const InputDecoration(
                    labelText: 'Target Area (optional)',
                    hintText: 'e.g. Kingston, St. Catherine...',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (titleController.text.isEmpty ||
                          messageController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Title and message are required')),
                        );
                        return;
                      }

                      if (severity == 'critical') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Confirm Critical Broadcast'),
                            content: const Text(
                                'This will send a critical alert to all users. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx, true),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('CONFIRM'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }

                      Navigator.pop(ctx);
                      final success = await ApiService.sendBroadcast(
                        title: titleController.text,
                        message: messageController.text,
                        severity: severity,
                        targetArea: targetAreaController.text.isNotEmpty
                            ? targetAreaController.text
                            : null,
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? 'Broadcast sent!'
                                : 'Failed to send broadcast'),
                            backgroundColor:
                                success ? Colors.green : Colors.red,
                          ),
                        );
                        if (success) _loadBroadcasts();
                      }
                    },
                    icon: const Icon(Icons.send),
                    label: const Text('Send Broadcast'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: severity == 'critical'
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _severityOption(String value, String label, Color color,
      String current, ValueChanged<String> onTap) {
    final isSelected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
