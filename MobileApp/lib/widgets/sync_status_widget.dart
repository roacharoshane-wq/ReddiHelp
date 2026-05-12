import 'package:flutter/material.dart';
//import 'package:provider/provider.dart';
import '../services/sync_service.dart';

class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({super.key});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  int _pendingCount = 0;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _updateCount();

    // Listen to sync service changes
    SyncService().addListener(_onSyncStatusChange);
  }

  @override
  void dispose() {
    SyncService().removeListener(_onSyncStatusChange);
    super.dispose();
  }

  void _onSyncStatusChange() {
    _updateCount();
  }

  Future<void> _updateCount() async {
    final count = SyncService().pendingCount;
    if (mounted) {
      setState(() {
        _pendingCount = count;
      });
    }
  }

  Future<void> _manualSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      final result = await SyncService().flush();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync completed: ${result.applied} applied, ${result.rejected} rejected',
            ),
            backgroundColor: result.hasErrors ? Colors.orange : Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      await _updateCount();
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingCount == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _manualSync,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isSyncing ? Colors.blue : Colors.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSyncing ? Icons.sync : Icons.sync_problem,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              _isSyncing ? 'Syncing...' : '$_pendingCount pending',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
