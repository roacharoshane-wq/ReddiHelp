// Feature #4 — Offline Banner Widget
// Displays a persistent banner when the device is offline,
// showing "Last updated X min ago" and pending sync count.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/sync_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;
  int _pendingCount = 0;
  DateTime? _lastOnline;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _checkNow();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _checkNow();
    });
  }

  Future<void> _checkNow() async {
    final offline = !await _hasInternetConnection();
    if (mounted) {
      setState(() {
        _isOffline = offline;
        if (!offline) _lastOnline = DateTime.now();
      });
      _refreshPending();
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  void _refreshPending() {
    final count = SyncService().pendingCount;
    if (mounted) setState(() => _pendingCount = count);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _timeAgo() {
    if (_lastOnline == null) return '';
    final diff = DateTime.now().difference(_lastOnline!);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline && _pendingCount == 0) return const SizedBox.shrink();

    return Material(
      color: _isOffline ? Colors.red[700] : Colors.orange[700],
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                _isOffline ? Icons.cloud_off : Icons.sync,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isOffline
                      ? 'You are offline${_lastOnline != null ? ' — last updated ${_timeAgo()}' : ''}'
                      : '$_pendingCount item${_pendingCount == 1 ? '' : 's'} syncing...',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (_pendingCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendingCount pending',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
