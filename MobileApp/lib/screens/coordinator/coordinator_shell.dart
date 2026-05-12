import 'package:flutter/material.dart';
import '../../widgets/role_bottom_app_bar.dart';
import 'coordinator_dashboard_screen.dart';
import 'coordinator_incidents_screen.dart';
import 'coordinator_volunteers_screen.dart';
import 'coordinator_broadcasts_screen.dart';
import '../responder_home_screen.dart';

class CoordinatorShell extends StatefulWidget {
  const CoordinatorShell({super.key});

  @override
  State<CoordinatorShell> createState() => _CoordinatorShellState();
}

class _CoordinatorShellState extends State<CoordinatorShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    CoordinatorDashboardScreen(),
    ResponderHomeScreen(),
    CoordinatorIncidentsScreen(),
    CoordinatorVolunteersScreen(),
    CoordinatorBroadcastsScreen(),
  ];

  static const List<RoleBottomBarItem> _items = [
    RoleBottomBarItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      tooltip: 'Dashboard',
    ),
    RoleBottomBarItem(
      icon: Icons.map_outlined,
      selectedIcon: Icons.map,
      tooltip: 'Map',
    ),
    RoleBottomBarItem(
      icon: Icons.warning_amber_outlined,
      selectedIcon: Icons.warning_amber,
      tooltip: 'Incidents',
    ),
    RoleBottomBarItem(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      tooltip: 'Volunteers',
    ),
    RoleBottomBarItem(
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
      tooltip: 'Broadcasts',
    ),
  ];

  // void _openQuickActions() {
  //   showModalBottomSheet(
  //     context: context,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  //     ),
  //     builder: (ctx) => Padding(
  //       padding: const EdgeInsets.all(20),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           const Text(
  //             'Quick Actions',
  //             style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  //           ),
  //           const SizedBox(height: 16),
  //           ListTile(
  //             leading: const CircleAvatar(
  //               backgroundColor: Color(0xFF00BFA5),
  //               child: Icon(Icons.people_rounded, color: Colors.white),
  //             ),
  //             title: const Text('Team'),
  //             subtitle: const Text('Open volunteer management'),
  //             onTap: () {
  //               Navigator.pop(ctx);
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (_) => const CoordinatorVolunteersScreen(),
  //                 ),
  //               );
  //             },
  //           ),
  //           ListTile(
  //             leading: const CircleAvatar(
  //               backgroundColor: Color(0xFFFB8C00),
  //               child: Icon(Icons.campaign_rounded, color: Colors.white),
  //             ),
  //             title: const Text('Broadcast'),
  //             subtitle: const Text('Compose or review alerts'),
  //             onTap: () {
  //               Navigator.pop(ctx);
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (_) => const CoordinatorBroadcastsScreen(),
  //                 ),
  //               );
  //             },
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  void _onSelected(int index) {
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
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      // floatingActionButton: FloatingActionButton(
      //   onPressed: _openQuickActions,
      //   backgroundColor: const Color(0xFF1657B7),
      //   child: const Icon(Icons.add, color: Colors.white),
      // ),
    );
  }
}
