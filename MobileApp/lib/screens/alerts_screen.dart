// Feature #13 Broadcast Alert Reception
// Full-screen alert modal for urgent coordinator broadcasts.
// Alerts tab showing history, with "I understand" acknowledgement.
// Polls /api/broadcasts for new alerts, shows full-screen modal for unread ones.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    // Poll for new broadcasts every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadAlerts(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAlerts({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final alerts = await ApiService.getBroadcasts();
      final role = Provider.of<AuthProvider>(context, listen: false).userRole;
      final filteredAlerts = _filterAlertsForRole(alerts, role);
      if (mounted) {
        setState(() {
          _alerts = filteredAlerts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _filterAlertsForRole(
    List<Map<String, dynamic>> alerts,
    String? userRole,
  ) {
    if (alerts.isEmpty) return alerts;
    return alerts
        .where((alert) => _matchesTargetRole(userRole, alert['target_roles']))
        .toList();
  }

  bool _matchesTargetRole(String? userRole, dynamic targetRole) {
    final normalizedTarget = _normalizeRoleValue(targetRole) ?? 'all';
    if (normalizedTarget == 'all') return true;

    final normalizedUser = _normalizeRoleValue(userRole);
    if (normalizedUser == null) return false;
    return normalizedTarget == normalizedUser;
  }

  String? _normalizeRoleValue(dynamic role) {
    if (role == null) return null;
    final value = role.toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'all') return 'all';
    final singular =
        value.endsWith('s') ? value.substring(0, value.length - 1) : value;
    const allowed = {
      'victim',
      'volunteer',
      'responder',
      'coordinator',
      'admin',
    };
    return allowed.contains(singular) ? singular : null;
  }

  // Show full-screen modal for unacknowledged alert (spec: explicit "I understand")
  void _showAlertModal(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog.fullscreen(
          child: Container(
            color: Colors.red[900],
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 80),
                    const SizedBox(height: 24),
                    const Text(
                      'EMERGENCY ALERT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        alert['message'] ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (alert['expires_at'] != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer,
                              color: Colors.white70, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Expires: ${_formatExpiry(alert['expires_at'])}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                    if (alert['created_at'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Issued: ${_formatTimestamp(alert['created_at'])}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Acknowledge the alert
                          final alertId = alert['id'];
                          if (alertId != null) {
                            ApiService.acknowledgeBroadcast(alertId);
                          }
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red[900],
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'I UNDERSTAND',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatExpiry(dynamic expiresAt) {
    try {
      final dt = DateTime.parse(expiresAt.toString());
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return 'Expired';
      if (diff.inHours > 0)
        return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
      return 'in ${diff.inMinutes}m';
    } catch (_) {
      return expiresAt.toString();
    }
  }

  String _formatTimestamp(dynamic ts) {
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Alerts'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No active alerts',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You will be notified if an emergency broadcast is issued for your area',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAlerts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _alerts.length,
                    itemBuilder: (ctx, i) => _buildAlertCard(_alerts[i]),
                  ),
                ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final isExpired = alert['expires_at'] != null &&
        DateTime.tryParse(alert['expires_at'].toString())
                ?.isBefore(DateTime.now()) ==
            true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      color: isExpired ? Colors.grey[100] : Colors.red[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAlertModal(alert),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: isExpired ? Colors.grey : Colors.red[700],
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Emergency Alert',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isExpired ? Colors.grey : Colors.red[800],
                      ),
                    ),
                  ),
                  if (isExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('EXPIRED',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                alert['message'] ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: isExpired ? Colors.grey[600] : Colors.black87,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (alert['created_at'] != null)
                    Text(
                      _formatTimestamp(alert['created_at']),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  const Spacer(),
                  if (alert['expires_at'] != null && !isExpired)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer, size: 14, color: Colors.orange[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Expires ${_formatExpiry(alert['expires_at'])}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange[700]),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
