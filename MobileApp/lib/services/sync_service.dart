import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';

class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _boxName = 'sync_queue';
  static const String _incidentBoxName = 'offline_incidents';

  // Set to true for debugging/testing without real OTP/JWT support.
  // WARNING: Do not enable in production if your backend rejects mock tokens.
  static const bool _allowMockTokenSync = true;

  late Box<String> _syncBox;
  late Box<Map> _incidentBox;
  bool _isInitialized = false;
  Timer? _periodicTimer;
  Timer? _connectivityTimer;

  // ============================================================
  // Initialisation
  // ============================================================

  Future<void> init() async {
    if (_isInitialized) return;

    await Hive.initFlutter();
    _syncBox = await Hive.openBox<String>(_boxName);
    _incidentBox = await Hive.openBox<Map>(_incidentBoxName);
    _isInitialized = true;

    _startConnectivityWatcher();

    // Periodic sync every 30 seconds
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _hasConnection().then((isOnline) {
        if (isOnline) {
          flush().catchError((e) {
            print('Periodic sync failed: $e');
            return SyncResult(applied: 0, rejected: 0, errors: [e.toString()]);
          });
        }
      });
    });

    print('✅ SyncService initialised with ${_syncBox.length} pending item(s)');
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // Internal box accessors
  // ============================================================

  Box<String> get _syncBoxInstance {
    if (!_isInitialized)
      throw Exception('SyncService not initialised – call init() first');
    return _syncBox;
  }

  Box<Map> get _incidentBoxInstance {
    if (!_isInitialized)
      throw Exception('SyncService not initialised – call init() first');
    return _incidentBox;
  }

  // ============================================================
  // Queue management
  // ============================================================

  /// Enqueues an action to be synced when the device comes back online.
  Future<void> enqueue({
    required String idempotencyKey,
    required String action,
    required String resource,
    required Map<String, dynamic> data,
  }) async {
    final entry = json.encode({
      'idempotencyKey': idempotencyKey,
      'action': action,
      'resource': resource,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await _syncBoxInstance.put(idempotencyKey, entry);
    print('📦 Enqueued $action for $resource: $idempotencyKey');
    notifyListeners();
  }

  /// Stores an incident in the local Hive box so it appears on-screen immediately.
  Future<void> storeIncidentLocally(Map<String, dynamic> incident) async {
    final id = incident['idempotencyKey'] ??
        incident['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await _incidentBoxInstance.put(id, incident);
    notifyListeners();
  }

  /// Returns all locally cached incidents (offline + unsynced).
  List<Map<String, dynamic>> getLocalIncidents() {
    return _incidentBoxInstance.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _getPending() {
    final entries = _syncBoxInstance.values
        .map((e) => json.decode(e) as Map<String, dynamic>)
        .toList();
    entries.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
    return entries;
  }

  /// Updates the status of a locally cached incident so the UI reflects
  /// the change immediately, even before the server confirms it.
  Future<void> updateLocalIncidentStatus(dynamic id, String newStatus) async {
    for (final key in _incidentBoxInstance.keys) {
      final entry = Map<String, dynamic>.from(_incidentBoxInstance.get(key)!);
      if (entry['id']?.toString() == id.toString()) {
        entry['status'] = newStatus;
        entry['lastUpdated'] = DateTime.now().toIso8601String();
        await _incidentBoxInstance.put(key, entry);
        notifyListeners();
        return;
      }
    }
  }

  // ============================================================
  // Flush – send all queued actions to the server
  // ============================================================

  Future<SyncResult> flush() async {
    final pending = _getPending();
    if (pending.isEmpty) {
      return SyncResult(applied: 0, rejected: 0, errors: []);
    }

    if (!await _hasConnection()) {
      throw Exception('No internet connection');
    }

    print('🔄 Flushing ${pending.length} pending item(s)...');

    try {
      final token = await AuthService().getAccessToken();
      if (token == null) {
        throw Exception('Not authenticated – no token available');
      }

      // Guard: mock tokens (generated locally during testing) cannot be
      // validated by the server's JWT middleware when using a real backend.
      // For debug/test use-cases with a mock-compatible backend, we may allow
      // syncing with mock tokens via _allowMockTokenSync.
      if (token.startsWith('mock_') && !_allowMockTokenSync) {
        print(
            'ℹ️  Mock token detected – skipping sync (no real JWT available)');
        print('   → Log in via the real OTP flow to enable syncing.');
        return SyncResult(applied: 0, rejected: 0, errors: []);
      }
      if (token.startsWith('mock_') && _allowMockTokenSync) {
        print(
            'ℹ️  Mock token detected but _allowMockTokenSync=true → continuing sync.');
      }

      Future<http.Response> sendRequest(String bearerToken) {
        return http
            .post(
              Uri.parse('${ApiService.baseUrl}/sync'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $bearerToken',
              },
              body: json.encode({'actions': pending}),
            )
            .timeout(const Duration(seconds: 30));
      }

      var response = await sendRequest(token);

      // On 401/403, attempt a single token refresh then retry once.
      if (response.statusCode == 401 || response.statusCode == 403) {
        print(
            '⚠️  Sync returned ${response.statusCode} – attempting token refresh...');
        final newToken = await AuthService().refreshAccessToken();
        if (newToken != null) {
          print('🔄 Retrying sync with refreshed token...');
          response = await sendRequest(newToken);
        } else {
          throw Exception('Token refresh failed – cannot sync');
        }
      }

      if (response.statusCode != 200) {
        throw Exception(
            'Sync failed: ${response.statusCode} – ${response.body}');
      }

      final Map<String, dynamic> responseData = json.decode(response.body);
      final List results = responseData['results'] ?? [];

      int applied = 0;
      int rejected = 0;
      final errors = <String>[];

      for (final r in results) {
        final status = r['status'] as String? ?? 'unknown';
        final idempotencyKey = r['idempotencyKey'] as String?;

        if (status == 'applied' || status == 'duplicate') {
          if (idempotencyKey != null) {
            await _syncBoxInstance.delete(idempotencyKey);
          }
          applied++;
        } else {
          rejected++;
          final reason = r['reason'] ?? 'Unknown error';
          errors.add('$idempotencyKey: $reason');
          print('⚠️ Sync rejected $idempotencyKey: $reason');
          // Remove permanently rejected items so they don't retry forever.
          // Transient errors (network, 5xx) are thrown as exceptions above
          // and never reach this branch.
          if (idempotencyKey != null) {
            await _syncBoxInstance.delete(idempotencyKey);
            print('🗑️ Removed permanently rejected item: $idempotencyKey');
          }
        }
      }

      print('✅ Sync complete – applied: $applied, rejected: $rejected');
      notifyListeners();
      return SyncResult(applied: applied, rejected: rejected, errors: errors);
    } catch (e) {
      print('❌ Sync failed: $e');
      throw Exception('Sync failed: $e');
    }
  }

  // ============================================================
  // Connectivity watcher – auto-flush when coming back online
  // ============================================================

  Future<bool> _hasConnection() async {
    try {
      Uri uri = Uri.parse(ApiService.baseUrl);
      if (uri.host.isEmpty) {
        uri = Uri.parse('http://${ApiService.baseUrl}');
      }
      final host = uri.host;
      final port = uri.hasPort
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startConnectivityWatcher() {
    bool wasOnline = true;
    bool checking = false;

    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (checking) return;
      checking = true;
      _hasConnection().then((isOnline) {
        if (isOnline && !wasOnline) {
          // Short delay to let the network stabilise before syncing.
          Future.delayed(const Duration(seconds: 2), () {
            flush().catchError((e) {
              print('Auto-sync failed: $e');
              return SyncResult(
                  applied: 0, rejected: 0, errors: [e.toString()]);
            });
          });
        }
        wasOnline = isOnline;
      }).whenComplete(() => checking = false);
    });
  }

  // ============================================================
  // Utilities
  // ============================================================

  int get pendingCount => _syncBoxInstance.length;

  Future<void> clearAll() async {
    await _syncBoxInstance.clear();
    await _incidentBoxInstance.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> getPendingByType(String resource) {
    return _getPending().where((item) => item['resource'] == resource).toList();
  }
}

// ============================================================
// SyncResult
// ============================================================

class SyncResult {
  final int applied;
  final int rejected;
  final List<String> errors;

  SyncResult({
    required this.applied,
    required this.rejected,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get total => applied + rejected;

  @override
  String toString() =>
      'SyncResult(applied: $applied, rejected: $rejected, errors: ${errors.length})';
}
