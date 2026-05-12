// Feature #13 — Broadcast Alert Reception
// Full-screen modal for urgent alerts (evacuation orders, etc.)
// Displays active alerts from backend, requires acknowledgement.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class BroadcastAlertsScreen extends StatefulWidget {
  const BroadcastAlertsScreen({super.key});

  @override
  State<BroadcastAlertsScreen> createState() => _BroadcastAlertsScreenState();
}

class _BroadcastAlertsScreenState extends State<BroadcastAlertsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAlerts();
    // Poll every 30 seconds for new alerts
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadAlerts(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAlerts(silent: true);
    }
  }

  Future<void> _loadAlerts({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final alerts = await ApiService.getActiveBroadcasts();
      final role = Provider.of<AuthProvider>(context, listen: false).userRole;
      final filteredAlerts = _filterAlertsForRole(alerts, role);
      if (mounted) {
        setState(() {
          _alerts = filteredAlerts;
          _loading = false;
        });
        // Show modal for any unacknowledged urgent alert
        if (filteredAlerts.isNotEmpty && !silent) {
          _showAlertModal(filteredAlerts.first);
        }
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

  void _showAlertModal(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AlertModal(
        alert: alert,
        onAcknowledge: () async {
          final alertId = alert['id'];
          if (alertId != null) {
            await ApiService.acknowledgeBroadcast(alertId);
          }
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  String _expiryCountdown(String? dateStr) {
    if (dateStr == null) return 'No expiry';
    try {
      final expiry = DateTime.parse(dateStr);
      final remaining = expiry.difference(DateTime.now());
      if (remaining.isNegative) return 'Expired';
      if (remaining.inHours > 0) return 'Expires in ${remaining.inHours}h';
      return 'Expires in ${remaining.inMinutes}m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcast Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlerts,
          ),
        ],
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
                        'You\'re safe — no emergency broadcasts right now',
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
    final message = alert['message'] ?? '';
    final createdAt = alert['created_at']?.toString();
    final expiresAt = alert['expires_at']?.toString();
    final targetRoles = alert['target_roles'] ?? 'all';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.deepOrange.withOpacity(0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.campaign,
                        color: Colors.deepOrange, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Emergency Broadcast',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.deepOrange,
                          ),
                        ),
                        Text(
                          'Target: ${targetRoles == 'all' ? 'Everyone' : targetRoles}',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    _timeAgo(createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _expiryCountdown(expiresAt),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showAlertModal(alert),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View Full Alert'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: const BorderSide(color: Colors.deepOrange),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen modal overlay for urgent broadcast alerts
class _AlertModal extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onAcknowledge;

  const _AlertModal({required this.alert, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final message = alert['message'] ?? '';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD32F2F), Color(0xFFE65100)],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 56),
            const SizedBox(height: 16),
            const Text(
              'EMERGENCY ALERT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAcknowledge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red[800],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'I UNDERSTAND',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
