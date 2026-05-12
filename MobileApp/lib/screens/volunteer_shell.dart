import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/role_bottom_app_bar.dart';
import 'broadcast_alerts_screen.dart';
import 'volunteer_home_screen.dart';
import 'volunteer_profile_screen.dart';
import 'volunteer_stats_screen.dart';
import 'volunteer_tasks_screen.dart';

class VolunteerShell extends StatefulWidget {
  const VolunteerShell({super.key});

  @override
  State<VolunteerShell> createState() => _VolunteerShellState();
}

class _VolunteerShellState extends State<VolunteerShell> {
  final GlobalKey _homeScreenKey = GlobalKey();
  int _currentIndex = 0;
  late final List<Widget> _screens;

  static const List<RoleBottomBarItem> _items = [
    RoleBottomBarItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      tooltip: 'Home',
    ),
    RoleBottomBarItem(
      icon: Icons.assignment_outlined,
      selectedIcon: Icons.assignment,
      tooltip: 'Tasks',
    ),
    RoleBottomBarItem(
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
      tooltip: 'Alerts',
    ),
    RoleBottomBarItem(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      tooltip: 'Stats',
    ),
    RoleBottomBarItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      tooltip: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      VolunteerHomeScreen(key: _homeScreenKey),
      const VolunteerTasksScreen(),
      const BroadcastAlertsScreen(),
      const VolunteerStatsScreen(),
      VolunteerProfileScreen(onComplete: _onProfileComplete),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPendingBroadcastAlert();
    });
  }

  void _onProfileComplete() {
    // Profile screen already handles success feedback.
  }

  void _onSelected(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  Future<void> _showPendingBroadcastAlert() async {
    try {
      final alerts = await ApiService.getActiveBroadcasts();
      if (!mounted || alerts.isEmpty) return;

      final alert = alerts.first;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _VolunteerAlertModal(
          alert: alert,
          onAcknowledge: () async {
            final alertId = alert['id'];
            if (alertId != null) {
              await ApiService.acknowledgeBroadcast(alertId);
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      );
    } catch (_) {
      // Ignore failures on first alert check.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: RoleBottomAppBar(
        items: _items,
        currentIndex: _currentIndex,
        onSelected: _onSelected,
      ),
    );
  }
}

class _VolunteerAlertModal extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onAcknowledge;

  const _VolunteerAlertModal({
    required this.alert,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final message = alert['message'] ?? 'Emergency broadcast alert.';
    final expiresAt = alert['expires_at']?.toString();
    return WillPopScope(
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
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (expiresAt != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Expires: $expiresAt',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onAcknowledge,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red[900],
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
    );
  }
}
