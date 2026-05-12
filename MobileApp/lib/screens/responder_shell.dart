import 'package:flutter/material.dart';

import '../widgets/role_bottom_app_bar.dart';
import 'broadcast_alerts_screen.dart';
import 'preparedness_guide_screen.dart';
import 'responder_home_screen.dart';
import 'responder_profile_screen.dart';

class ResponderShell extends StatefulWidget {
  const ResponderShell({super.key});

  @override
  State<ResponderShell> createState() => _ResponderShellState();
}

class _ResponderShellState extends State<ResponderShell> {
  int _currentIndex = 0;
  late final List<Widget> _screens;
  final GlobalKey _homeKey = GlobalKey();

  static const List<RoleBottomBarItem> _items = [
    RoleBottomBarItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      tooltip: 'Home',
    ),
    RoleBottomBarItem(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      tooltip: 'Preparedness',
    ),
    RoleBottomBarItem(
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
      tooltip: 'Broadcasts',
    ),
    RoleBottomBarItem(
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
      tooltip: 'All Incidents',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      ResponderHomeScreen(key: _homeKey),
      const PreparednessGuideScreen(),
      const BroadcastAlertsScreen(),
      ResponderProfileScreen(onComplete: _onProfileComplete),
    ];
  }

  void _onProfileComplete() {
    // No-op shell callback.
  }

  void _openAllIncidents() {
    final state = _homeKey.currentState;
    if (state != null) {
      (state as dynamic).showAllIncidents();
      return;
    }

    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = _homeKey.currentState;
      if (current != null) {
        (current as dynamic).showAllIncidents();
      }
    });
  }

  void _onSelected(int index) {
    if (index == 3) {
      _openAllIncidents();
      return;
    }
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
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
