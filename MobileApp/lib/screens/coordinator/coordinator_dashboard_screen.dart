// import 'package:flutter/material.dart';
// import 'dart:async';
// import '../../services/api_service.dart';
// import '../../models/incident.dart';
// import '../../models/stats.dart';
// import '../../providers/auth_provider.dart';
// import 'package:provider/provider.dart';

// class CoordinatorDashboardScreen extends StatefulWidget {
//   const CoordinatorDashboardScreen({super.key});

//   @override
//   State<CoordinatorDashboardScreen> createState() =>
//       _CoordinatorDashboardScreenState();
// }

// class _CoordinatorDashboardScreenState
//     extends State<CoordinatorDashboardScreen> {
//   Stats? _stats;
//   List<Incident> _incidents = [];
//   List<Map<String, dynamic>> _volunteers = [];
//   Map<String, dynamic> _healthScore = {};
//   Map<String, dynamic> _responseTimes = {};
//   Map<String, dynamic> _deployment = {};
//   bool _loading = true;
//   String? _expandedKpi;
//   Timer? _refreshTimer;

//   @override
//   void initState() {
//     super.initState();
//     _loadData();
//     _refreshTimer =
//         Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
//   }

//   @override
//   void dispose() {
//     _refreshTimer?.cancel();
//     super.dispose();
//   }

//   Future<void> _loadData() async {
//     try {
//       final results = await Future.wait([
//         ApiService.getStats(),
//         ApiService.getIncidents(),
//         ApiService.getVolunteers(),
//         ApiService.getAnalyticsHealthScore(),
//         ApiService.getAnalyticsResponseTimes(),
//         ApiService.getVolunteerDeployment(),
//       ]);

//       if (!mounted) return;
//       setState(() {
//         _stats = results[0] as Stats;
//         _incidents = results[1] as List<Incident>;
//         _volunteers = results[2] as List<Map<String, dynamic>>;
//         _healthScore = results[3] as Map<String, dynamic>;
//         _responseTimes = results[4] as Map<String, dynamic>;
//         _deployment = results[5] as Map<String, dynamic>;
//         _loading = false;
//       });
//     } catch (e) {
//       if (mounted) {
//         setState(() => _loading = false);
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final auth = Provider.of<AuthProvider>(context, listen: false);
//     final username = auth.user?['username'] ?? 'Coordinator';
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;

//     return Scaffold(
//       appBar: AppBar(
//         title: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Welcome back, $username',
//                 style: const TextStyle(fontSize: 18)),
//             if (_stats != null)
//               Text(
//                 '${_stats!.activeIncidents} active incidents',
//                 style:
//                     const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
//               ),
//           ],
//         ),
//         actions: [
//           _buildHealthBadge(),
//           const SizedBox(width: 8),
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _loadData,
//           ),
//         ],
//       ),
//       body: _loading
//           ? const Center(child: CircularProgressIndicator())
//           : RefreshIndicator(
//               onRefresh: _loadData,
//               child: SingleChildScrollView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     _buildKpiGrid(isDark),
//                     if (_expandedKpi != null) ...[
//                       const SizedBox(height: 12),
//                       _buildExpandedKpiList(isDark),
//                     ],
//                     const SizedBox(height: 20),
//                     _buildQuickStats(isDark),
//                     const SizedBox(height: 20),
//                     _buildRecentIncidents(isDark),
//                     const SizedBox(height: 20),
//                     _buildActiveVolunteers(isDark),
//                     const SizedBox(height: 20),
//                   ],
//                 ),
//               ),
//             ),
//     );
//   }

//   Widget _buildHealthBadge() {
//     final status = _healthScore['status'] ?? 'green';
//     Color color;
//     IconData icon;
//     switch (status) {
//       case 'red':
//         color = Colors.red;
//         icon = Icons.error;
//         break;
//       case 'amber':
//         color = Colors.orange;
//         icon = Icons.warning;
//         break;
//       default:
//         color = const Color(0xFF22C55E);
//         icon = Icons.check_circle;
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.15),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(icon, color: color, size: 16),
//           const SizedBox(width: 4),
//           Text(
//             status.toUpperCase(),
//             style: TextStyle(
//               color: color,
//               fontSize: 11,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildKpiGrid(bool isDark) {
//     final unassigned = _incidents
//         .where((i) => i.assignedTo == null && i.status != 'resolved')
//         .length;
//     final inProgress =
//         _incidents.where((i) => i.status == 'in-progress').length;
//     final resolved = _incidents.where((i) => i.status == 'resolved').length;

//     return GridView.count(
//       shrinkWrap: true,
//       physics: const NeverScrollableScrollPhysics(),
//       crossAxisCount: 2,
//       childAspectRatio: 1.5,
//       crossAxisSpacing: 12,
//       mainAxisSpacing: 12,
//       children: [
//         _buildKpiCard(
//           title: 'Unassigned',
//           value: unassigned.toString(),
//           icon: Icons.assignment_late,
//           color: const Color(0xFFEF4444),
//           isDark: isDark,
//           kpiKey: 'unassigned',
//         ),
//         _buildKpiCard(
//           title: 'Total Incidents',
//           value: (_stats?.totalIncidents ?? _incidents.length).toString(),
//           icon: Icons.warning_amber_rounded,
//           color: const Color(0xFF3B82F6),
//           isDark: isDark,
//           kpiKey: 'total',
//         ),
//         _buildKpiCard(
//           title: 'In Progress',
//           value: inProgress.toString(),
//           icon: Icons.autorenew,
//           color: const Color(0xFFF97316),
//           isDark: isDark,
//           kpiKey: 'in-progress',
//         ),
//         _buildKpiCard(
//           title: 'Resolved',
//           value: resolved.toString(),
//           icon: Icons.check_circle_outline,
//           color: const Color(0xFF14B8A6),
//           isDark: isDark,
//           kpiKey: 'resolved',
//         ),
//       ],
//     );
//   }

//   Widget _buildKpiCard({
//     required String title,
//     required String value,
//     required IconData icon,
//     required Color color,
//     required bool isDark,
//     required String kpiKey,
//   }) {
//     final isExpanded = _expandedKpi == kpiKey;

//     return GestureDetector(
//       onTap: () => setState(() {
//         _expandedKpi = isExpanded ? null : kpiKey;
//       }),
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 200),
//         decoration: BoxDecoration(
//           color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: isExpanded
//               ? Border.all(color: color, width: 2)
//               : Border.all(color: Colors.transparent),
//           boxShadow: [
//             BoxShadow(
//               color: isExpanded
//                   ? color.withOpacity(0.2)
//                   : Colors.black.withOpacity(0.05),
//               blurRadius: isExpanded ? 12 : 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Padding(
//           padding: const EdgeInsets.all(14),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Row(
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.all(8),
//                     decoration: BoxDecoration(
//                       color: color.withOpacity(0.12),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Icon(icon, color: color, size: 20),
//                   ),
//                   const Spacer(),
//                   Icon(
//                     isExpanded
//                         ? Icons.keyboard_arrow_up
//                         : Icons.keyboard_arrow_down,
//                     color: Colors.grey,
//                     size: 20,
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 value,
//                 style: TextStyle(
//                   fontSize: 28,
//                   fontWeight: FontWeight.bold,
//                   color: color,
//                 ),
//               ),
//               Text(
//                 title,
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: isDark ? Colors.grey[400] : Colors.grey[600],
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildExpandedKpiList(bool isDark) {
//     List<Incident> filtered;
//     String sectionTitle;

//     switch (_expandedKpi) {
//       case 'unassigned':
//         filtered = _incidents
//             .where((i) => i.assignedTo == null && i.status != 'resolved')
//             .toList();
//         sectionTitle = 'Unassigned Incidents';
//         break;
//       case 'in-progress':
//         filtered = _incidents.where((i) => i.status == 'in-progress').toList();
//         sectionTitle = 'In-Progress Incidents';
//         break;
//       case 'resolved':
//         filtered = _incidents.where((i) => i.status == 'resolved').toList();
//         sectionTitle = 'Resolved Incidents';
//         break;
//       default:
//         filtered = _incidents;
//         sectionTitle = 'All Incidents';
//     }

//     filtered.sort((a, b) => b.severity.compareTo(a.severity));

//     return Card(
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Text(
//                   sectionTitle,
//                   style: const TextStyle(
//                       fontSize: 16, fontWeight: FontWeight.bold),
//                 ),
//                 const Spacer(),
//                 Text(
//                   '${filtered.length} items',
//                   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                 ),
//               ],
//             ),
//             const Divider(),
//             if (filtered.isEmpty)
//               const Padding(
//                 padding: EdgeInsets.all(16),
//                 child: Center(
//                   child: Text('No incidents',
//                       style: TextStyle(color: Colors.grey)),
//                 ),
//               )
//             else
//               ...filtered.take(8).map((inc) => _buildExpandedIncidentRow(inc)),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildExpandedIncidentRow(Incident inc) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(
//         children: [
//           Container(
//             width: 4,
//             height: 40,
//             decoration: BoxDecoration(
//               color: _severityColor(inc.severity),
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),
//           const SizedBox(width: 10),
//           Text(_typeEmoji(inc.type), style: const TextStyle(fontSize: 18)),
//           const SizedBox(width: 10),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   '#${inc.id} — ${inc.areaId}',
//                   style: const TextStyle(
//                       fontWeight: FontWeight.w600, fontSize: 13),
//                 ),
//                 Text(
//                   inc.description,
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                 ),
//               ],
//             ),
//           ),
//           if (inc.responderName != null)
//             Chip(
//               label: Text(inc.responderName!,
//                   style: const TextStyle(fontSize: 10)),
//               padding: EdgeInsets.zero,
//               materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
//               visualDensity: VisualDensity.compact,
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildQuickStats(bool isDark) {
//     final avgResponse = _responseTimes['avgMinutes'] ?? 0;
//     final sampleSize = _responseTimes['sampleSize'] ?? 0;
//     final available = _deployment['available'] ?? 0;
//     final onTask = _deployment['onTask'] ?? 0;

//     return Row(
//       children: [
//         Expanded(
//           child: _buildQuickStatCard(
//             icon: Icons.timer_outlined,
//             label: 'Avg Response',
//             value:
//                 '${(avgResponse is num ? avgResponse.toStringAsFixed(1) : avgResponse)}m',
//             subLabel: '$sampleSize samples',
//             color: const Color(0xFF8B5CF6),
//             isDark: isDark,
//           ),
//         ),
//         const SizedBox(width: 12),
//         Expanded(
//           child: _buildQuickStatCard(
//             icon: Icons.people_outline,
//             label: 'Available',
//             value: available.toString(),
//             subLabel: '$onTask on task',
//             color: const Color(0xFF22C55E),
//             isDark: isDark,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildQuickStatCard({
//     required IconData icon,
//     required String label,
//     required String value,
//     required String subLabel,
//     required Color color,
//     required bool isDark,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 8,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(10),
//             decoration: BoxDecoration(
//               color: color.withOpacity(0.12),
//               borderRadius: BorderRadius.circular(10),
//             ),
//             child: Icon(icon, color: color, size: 22),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(label,
//                     style: TextStyle(fontSize: 11, color: Colors.grey[600])),
//                 Text(value,
//                     style: TextStyle(
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                         color: color)),
//                 Text(subLabel,
//                     style: TextStyle(fontSize: 10, color: Colors.grey[500])),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildRecentIncidents(bool isDark) {
//     final recent = List<Incident>.from(_incidents)
//       ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
//     final display = recent.take(8).toList();

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Icon(Icons.access_time, color: Colors.grey[600], size: 18),
//             const SizedBox(width: 6),
//             const Text(
//               'Recent Incidents',
//               style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//             ),
//             const Spacer(),
//             Text(
//               '${display.length} of ${_incidents.length}',
//               style: TextStyle(fontSize: 12, color: Colors.grey[500]),
//             ),
//           ],
//         ),
//         const SizedBox(height: 10),
//         ...display.map((inc) => _buildRecentIncidentCard(inc, isDark)),
//       ],
//     );
//   }

//   Widget _buildRecentIncidentCard(Incident inc, bool isDark) {
//     return Card(
//       margin: const EdgeInsets.only(bottom: 8),
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: IntrinsicHeight(
//         child: Row(
//           children: [
//             Container(
//               width: 5,
//               decoration: BoxDecoration(
//                 color: _severityColor(inc.severity),
//                 borderRadius: const BorderRadius.only(
//                   topLeft: Radius.circular(12),
//                   bottomLeft: Radius.circular(12),
//                 ),
//               ),
//             ),
//             Expanded(
//               child: Padding(
//                 padding:
//                     const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//                 child: Row(
//                   children: [
//                     Text(_typeEmoji(inc.type),
//                         style: const TextStyle(fontSize: 20)),
//                     const SizedBox(width: 10),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             '#${inc.id} ${inc.type[0].toUpperCase()}${inc.type.substring(1)}',
//                             style: const TextStyle(
//                                 fontWeight: FontWeight.w600, fontSize: 13),
//                           ),
//                           Text(
//                             '${inc.areaId} — ${inc.description}',
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: TextStyle(
//                                 fontSize: 12, color: Colors.grey[600]),
//                           ),
//                         ],
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.end,
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         _buildStatusBadge(inc.status),
//                         const SizedBox(height: 4),
//                         Text(
//                           _formatTimeAgo(inc.timestamp),
//                           style:
//                               TextStyle(fontSize: 10, color: Colors.grey[500]),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildActiveVolunteers(bool isDark) {
//     final activeVols = _volunteers
//         .where((v) =>
//             v['availability'] == 'available' || v['availability'] == 'on_task')
//         .take(8)
//         .toList();

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Icon(Icons.people, color: Colors.grey[600], size: 18),
//             const SizedBox(width: 6),
//             const Text(
//               'Active Volunteers',
//               style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//             ),
//             const Spacer(),
//             Text(
//               '${activeVols.length} online',
//               style: TextStyle(fontSize: 12, color: Colors.grey[500]),
//             ),
//           ],
//         ),
//         const SizedBox(height: 10),
//         if (activeVols.isEmpty)
//           Card(
//             shape:
//                 RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//             child: const Padding(
//               padding: EdgeInsets.all(20),
//               child: Center(
//                 child: Text('No volunteers online',
//                     style: TextStyle(color: Colors.grey)),
//               ),
//             ),
//           )
//         else
//           ...activeVols.map((v) => _buildVolunteerRow(v, isDark)),
//       ],
//     );
//   }

//   Widget _buildVolunteerRow(Map<String, dynamic> v, bool isDark) {
//     final name = v['username'] ?? 'Unknown';
//     final role = v['role'] ?? 'volunteer';
//     final availability = v['availability'] ?? 'offline';
//     final activeTasks = v['activeTaskCount'] ?? 0;
//     final isAvailable = availability == 'available';

//     return Card(
//       margin: const EdgeInsets.only(bottom: 6),
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
//         child: Row(
//           children: [
//             Stack(
//               children: [
//                 CircleAvatar(
//                   radius: 20,
//                   backgroundColor: const Color(0xFF0D9488).withOpacity(0.15),
//                   child: Text(
//                     name[0].toUpperCase(),
//                     style: const TextStyle(
//                       color: Color(0xFF0D9488),
//                       fontWeight: FontWeight.bold,
//                       fontSize: 16,
//                     ),
//                   ),
//                 ),
//                 Positioned(
//                   bottom: 0,
//                   right: 0,
//                   child: Container(
//                     width: 12,
//                     height: 12,
//                     decoration: BoxDecoration(
//                       color: isAvailable
//                           ? const Color(0xFF22C55E)
//                           : const Color(0xFF3B82F6),
//                       shape: BoxShape.circle,
//                       border: Border.all(
//                         color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
//                         width: 2,
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(name,
//                       style: const TextStyle(
//                           fontWeight: FontWeight.w600, fontSize: 14)),
//                   Text(
//                     '${_roleEmoji(role)} $role',
//                     style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//                   ),
//                 ],
//               ),
//             ),
//             if (activeTasks > 0)
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF3B82F6).withOpacity(0.12),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   '$activeTasks task${activeTasks == 1 ? '' : 's'}',
//                   style: const TextStyle(
//                     fontSize: 11,
//                     color: Color(0xFF3B82F6),
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildStatusBadge(String status) {
//     Color bg, fg;
//     switch (status) {
//       case 'active':
//         bg = const Color(0xFF3B82F6).withOpacity(0.12);
//         fg = const Color(0xFF3B82F6);
//         break;
//       case 'in-progress':
//         bg = const Color(0xFFF97316).withOpacity(0.12);
//         fg = const Color(0xFFF97316);
//         break;
//       case 'resolved':
//         bg = const Color(0xFF22C55E).withOpacity(0.12);
//         fg = const Color(0xFF22C55E);
//         break;
//       default:
//         bg = Colors.grey.withOpacity(0.12);
//         fg = Colors.grey;
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//       decoration: BoxDecoration(
//         color: bg,
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: Text(
//         status.toUpperCase(),
//         style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold),
//       ),
//     );
//   }

//   Color _severityColor(int severity) {
//     if (severity >= 5) return const Color(0xFF991B1B);
//     if (severity >= 4) return const Color(0xFFEF4444);
//     if (severity >= 3) return const Color(0xFFF97316);
//     if (severity >= 2) return const Color(0xFFEAB308);
//     return const Color(0xFF22C55E);
//   }

//   String _typeEmoji(String type) {
//     switch (type) {
//       case 'medical':
//       case 'medical_emergency':
//         return '🏥';
//       case 'fire':
//         return '🔥';
//       case 'flood':
//         return '🌊';
//       case 'trapped':
//         return '⚠️';
//       case 'supplies':
//       case 'need_supplies':
//         return '📦';
//       case 'shelter':
//       case 'need_shelter':
//         return '🏠';
//       default:
//         return '⚠️';
//     }
//   }

//   String _roleEmoji(String role) {
//     switch (role) {
//       case 'medical_professional':
//         return '🏥';
//       case 'fire_rescue':
//         return '🚒';
//       case 'search_rescue':
//         return '🔍';
//       case 'logistics':
//         return '📦';
//       default:
//         return '🤝';
//     }
//   }

//   String _formatTimeAgo(DateTime timestamp) {
//     final diff = DateTime.now().difference(timestamp);
//     if (diff.inDays > 0) return '${diff.inDays}d ago';
//     if (diff.inHours > 0) return '${diff.inHours}h ago';
//     if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
//     return 'Just now';
//   }
// }

import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/api_service.dart';
import '../../models/incident.dart';
import '../../models/stats.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../widgets/redihelp_overlays.dart';
import '../chat_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _primaryBlue = Color(0xFF1A73E8);
const _teal = Color(0xFF00BFA5);
const _orange = Color(0xFFFB8C00);
const _danger = Color(0xFFE53935);

class CoordinatorDashboardScreen extends StatefulWidget {
  const CoordinatorDashboardScreen({super.key});

  @override
  State<CoordinatorDashboardScreen> createState() =>
      _CoordinatorDashboardScreenState();
}

class _CoordinatorDashboardScreenState
    extends State<CoordinatorDashboardScreen> {
  Stats? _stats;
  List<Incident> _incidents = [];
  List<Map<String, dynamic>> _volunteers = [];
  Map<String, dynamic> _healthScore = {};
  Map<String, dynamic> _responseTimes = {};
  Map<String, dynamic> _deployment = {};
  bool _loading = true;
  String? _expandedKpi;
  Timer? _refreshTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getStats(),
        ApiService.getIncidents(),
        ApiService.getVolunteers(),
        ApiService.getAnalyticsHealthScore(),
        ApiService.getAnalyticsResponseTimes(),
        ApiService.getVolunteerDeployment(),
      ]);

      if (!mounted) return;
      setState(() {
        _stats = results[0] as Stats;
        _incidents = results[1] as List<Incident>;
        _volunteers = results[2] as List<Map<String, dynamic>>;
        _healthScore = results[3] as Map<String, dynamic>;
        _responseTimes = results[4] as Map<String, dynamic>;
        _deployment = results[5] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final username = auth.user?['username'] ?? 'Coordinator';

    return Scaffold(
      // ── App bar ─────────────────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(84),
        child: AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00BFA5), Color(0xFF1A73E8)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome back, $username',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_stats != null)
                Text(
                  '${_stats!.activeIncidents} active incidents',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          actions: [
            _buildHealthBadge(),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => showProfileSkillsSheet(
                context,
                title: 'Coordinator Profile & Skills',
                primaryFieldLabel: 'Department / Office',
                primaryFieldKey: 'department',
                fallbackInitial:
                    username.isNotEmpty ? username[0].toUpperCase() : 'C',
                accentColor: _primaryBlue,
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: Colors.white,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'C',
                    style: const TextStyle(
                      color: _primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Body ──────────────────────────────────────────────────────────────
      backgroundColor: const Color(0xFFF3F4F6),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _primaryBlue),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _primaryBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKpiGrid(),
                    if (_expandedKpi != null) ...[
                      const SizedBox(height: 12),
                      _buildExpandedKpiList(),
                    ],
                    const SizedBox(height: 20),
                    _buildQuickStats(),
                    const SizedBox(height: 20),
                    _buildRecentIncidents(),
                    const SizedBox(height: 20),
                    _buildActiveVolunteers(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

      // ── Speed dial FAB handled by shell ────────────────────────────────
      floatingActionButton: null,
    );
  }

  // ── Health badge ───────────────────────────────────────────────────────────

  Widget _buildHealthBadge() {
    final score = _healthScore['score'] ?? 'green';
    Color dotColor;
    String label;
    switch (score) {
      case 'red':
        dotColor = _danger;
        label = 'RED';
        break;
      case 'amber':
        dotColor = _orange;
        label = 'AMBER';
        break;
      default:
        dotColor = const Color(0xFF22C55E);
        label = 'GREEN';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF16A34A),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI grid ───────────────────────────────────────────────────────────────

  Widget _buildKpiGrid() {
    final unassigned = _incidents
        .where((i) => i.assignedTo == null && i.status != 'resolved')
        .length;
    final inProgress =
        _incidents.where((i) => i.status == 'in-progress').length;
    final resolved = _incidents.where((i) => i.status == 'resolved').length;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.32,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildKpiCard(
          title: 'Unassigned',
          value: unassigned.toString(),
          icon: Icons.assignment_late_rounded,
          color: _danger,
          kpiKey: 'unassigned',
        ),
        _buildKpiCard(
          title: 'Total Incidents',
          value: (_stats?.totalIncidents ?? _incidents.length).toString(),
          icon: Icons.warning_amber_rounded,
          color: _primaryBlue,
          kpiKey: 'total',
        ),
        _buildKpiCard(
          title: 'In Progress',
          value: inProgress.toString(),
          icon: Icons.autorenew_rounded,
          color: _orange,
          kpiKey: 'in-progress',
        ),
        _buildKpiCard(
          title: 'Resolved',
          value: resolved.toString(),
          icon: Icons.check_circle_outline_rounded,
          color: _teal,
          kpiKey: 'resolved',
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String kpiKey,
  }) {
    final isExpanded = _expandedKpi == kpiKey;

    return GestureDetector(
      onTap: () => setState(() {
        _expandedKpi = isExpanded ? null : kpiKey;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isExpanded
              ? Border.all(color: color, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
              color: isExpanded
                  ? color.withOpacity(0.15)
                  : Colors.black.withOpacity(0.06),
              blurRadius: isExpanded ? 18 : 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                ],
              ),
              // FittedBox prevents the "BOTTOM OVERFLOWED BY 18 PIXELS" error
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Expanded KPI list ──────────────────────────────────────────────────────

  Widget _buildExpandedKpiList() {
    List<Incident> filtered;
    String sectionTitle;

    switch (_expandedKpi) {
      case 'unassigned':
        filtered = _incidents
            .where((i) => i.assignedTo == null && i.status != 'resolved')
            .toList();
        sectionTitle = 'Unassigned Incidents';
        break;
      case 'in-progress':
        filtered = _incidents.where((i) => i.status == 'in-progress').toList();
        sectionTitle = 'In-Progress Incidents';
        break;
      case 'resolved':
        filtered = _incidents.where((i) => i.status == 'resolved').toList();
        sectionTitle = 'Resolved Incidents';
        break;
      default:
        filtered = _incidents;
        sectionTitle = 'All Incidents';
    }

    filtered.sort((a, b) => b.severity.compareTo(a.severity));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(sectionTitle,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _primaryBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${filtered.length} items',
                  style: const TextStyle(
                      fontSize: 11,
                      color: _primaryBlue,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 4),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child:
                    Text('No incidents', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...filtered.take(8).map(_buildExpandedIncidentRow),
        ],
      ),
    );
  }

  Widget _buildExpandedIncidentRow(Incident inc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: InkWell(
        onTap: () => _showIncidentDetailSheet(inc),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: _severityColor(inc.severity),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(_typeEmoji(inc.type), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${inc.id} — ${inc.areaId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(inc.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            if (inc.responderName != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  inc.responderName!,
                  style: const TextStyle(
                      fontSize: 10, color: _teal, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Quick stats ────────────────────────────────────────────────────────────

  Widget _buildQuickStats() {
    final avgResponse = _responseTimes['avgMinutes'] ?? 0;
    final sampleSize = _responseTimes['sampleSize'] ?? 0;
    final available = _deployment['available'] ?? 0;
    final onTask = _deployment['onTask'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.timer_outlined,
            label: 'Avg Response',
            value:
                '${(avgResponse is num ? avgResponse.toStringAsFixed(1) : avgResponse)}m',
            subLabel: '$sampleSize samples',
            color: const Color(0xFF8B5CF6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            icon: Icons.people_outline_rounded,
            label: 'Available',
            value: available.toString(),
            subLabel: '$onTask on task',
            color: const Color(0xFF22C55E),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String subLabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                Text(subLabel,
                    style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Recent incidents ───────────────────────────────────────────────────────

  Widget _buildRecentIncidents() {
    final recent = List<Incident>.from(_incidents)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final display = recent.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.access_time_rounded, color: Colors.grey, size: 18),
            const SizedBox(width: 6),
            const Text('Recent Incidents',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${display.length} of ${_incidents.length}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...display.map(_buildRecentIncidentCard),
      ],
    );
  }

  Widget _buildRecentIncidentCard(Incident inc) {
    return GestureDetector(
      onTap: () => _showIncidentDetailSheet(inc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 5, color: _severityColor(inc.severity)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    child: Row(
                      children: [
                        Text(_typeEmoji(inc.type),
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${inc.id} ${inc.type[0].toUpperCase()}${inc.type.substring(1)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Text(
                                '${inc.areaId} — ${inc.description}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStatusBadge(inc.status),
                            const SizedBox(height: 4),
                            Text(_formatTimeAgo(inc.timestamp),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[400])),
                          ],
                        ),
                      ],
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

  void _showIncidentDetailSheet(Incident incident) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
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
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _severityColor(incident.severity),
                  child: Text(
                    _typeEmoji(incident.type),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${incident.id} ${incident.type[0].toUpperCase()}${incident.type.substring(1)}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        incident.areaId,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(incident.status),
              ],
            ),
            const SizedBox(height: 16),
            _detailCard('Incident Details', [
              _detailRow(Icons.category, 'Type', incident.type),
              _detailRow(Icons.location_on, 'Location', incident.areaId),
              _detailRow(Icons.access_time, 'Timestamp',
                  _formatTimeAgo(incident.timestamp)),
              if (incident.description.isNotEmpty)
                _detailRow(
                    Icons.description, 'Description', incident.description),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        incidentId: incident.id,
                        incidentType: incident.type,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Open Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryBlue,
                  side: const BorderSide(color: _primaryBlue),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  // ── Active volunteers ──────────────────────────────────────────────────────

  Widget _buildActiveVolunteers() {
    final activeVols = _volunteers
        .where((v) =>
            v['availability'] == 'available' || v['availability'] == 'on_task')
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_rounded, color: Colors.grey, size: 18),
            const SizedBox(width: 6),
            const Text('Active Volunteers',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${activeVols.length} online',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (activeVols.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('No volunteers online',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...activeVols.map(_buildVolunteerRow),
      ],
    );
  }

  Widget _buildVolunteerRow(Map<String, dynamic> v) {
    final name = v['username'] ?? 'Unknown';
    final role = v['role'] ?? 'volunteer';
    final availability = v['availability'] ?? 'offline';
    final activeTasks = v['activeTaskCount'] ?? 0;
    final isAvailable = availability == 'available';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _teal.withOpacity(0.13),
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isAvailable ? const Color(0xFF22C55E) : _primaryBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text('${_roleEmoji(role)} $role',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          if (activeTasks > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _primaryBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$activeTasks task${activeTasks == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  color: _primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Status badge ───────────────────────────────────────────────────────────

  Widget _buildStatusBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'active':
        bg = _primaryBlue.withOpacity(0.10);
        fg = _primaryBlue;
        break;
      case 'in-progress':
        bg = _orange.withOpacity(0.10);
        fg = _orange;
        break;
      case 'resolved':
        bg = const Color(0xFF22C55E).withOpacity(0.10);
        fg = const Color(0xFF22C55E);
        break;
      default:
        bg = Colors.grey.withOpacity(0.10);
        fg = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            color: fg,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color _severityColor(int severity) {
    if (severity >= 5) return const Color(0xFF991B1B);
    if (severity >= 4) return _danger;
    if (severity >= 3) return _orange;
    if (severity >= 2) return const Color(0xFFEAB308);
    return const Color(0xFF22C55E);
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'medical':
      case 'medical_emergency':
        return '🏥';
      case 'fire':
        return '🔥';
      case 'flood':
        return '🌊';
      case 'trapped':
        return '⚠️';
      case 'supplies':
      case 'need_supplies':
        return '📦';
      case 'shelter':
      case 'need_shelter':
        return '🏠';
      default:
        return '⚠️';
    }
  }

  String _roleEmoji(String role) {
    switch (role) {
      case 'medical_professional':
        return '🏥';
      case 'fire_rescue':
        return '🚒';
      case 'search_rescue':
        return '🔍';
      case 'logistics':
        return '📦';
      default:
        return '🤝';
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
