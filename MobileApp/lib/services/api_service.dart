import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:MobileApp/models/police_station.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import '../config/app_config.dart';
import '../models/incident.dart';
import '../models/resource.dart';
import '../models/stats.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get socketBaseUrl => AppConfig.socketBaseUrl;

  static final AuthService _authService = AuthService();
  static final SyncService _syncService = SyncService();
  static const Duration _defaultRequestTimeout = Duration(seconds: 12);
  static const int _defaultRetryCount = 1;

  // Cached local instruction snippets (loaded from assets/data/incident_instructions.json)
  static Map<String, dynamic>? _localInstructionsCache;

  static Future<void> _loadLocalInstructions() async {
    if (_localInstructionsCache != null) return;
    try {
      final raw =
          await rootBundle.loadString('assets/data/incident_instructions.json');
      _localInstructionsCache = json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      _localInstructionsCache = {};
    }
  }

  /// Returns a short instruction snippet for [type] from bundled assets.
  static Future<String?> getLocalInstructionSnippet(String type) async {
    await _loadLocalInstructions();
    if (_localInstructionsCache == null) return null;
    final entry = _localInstructionsCache![type];
    if (entry == null) return null;
    return (entry['snippet'] as String?)?.trim();
  }

  // ============================================================
  // Headers
  // ============================================================

  /// Returns auth headers. Exposed so SyncService can reuse this if needed.
  static Future<Map<String, String>> getHeaders() async {
    return _getHeaders();
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await _authService.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // Auto-refresh wrapper
  // ============================================================

  /// Sends [requestFn]. On 401, attempts a token refresh and retries once.
  static Future<http.Response> _requestWithAuth(
    Future<http.Response> Function() requestFn, {
    Duration timeout = _defaultRequestTimeout,
    int retries = _defaultRetryCount,
  }) async {
    final retryCount = retries < 0 ? 0 : retries;

    for (var attempt = 0; attempt <= retryCount; attempt++) {
      try {
        var response = await requestFn().timeout(timeout);

        if (response.statusCode == 401) {
          final newToken = await _authService.refreshAccessToken();
          if (newToken != null) {
            response = await requestFn().timeout(timeout);
          }
        }

        if (response.statusCode >= 500 && attempt < retryCount) {
          final nextTry = attempt + 2;
          print(
              '⚠️ [ApiService] Server error ${response.statusCode}, retrying ($nextTry/${retryCount + 1})');
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }

        return response;
      } catch (error) {
        final canRetry = (error is TimeoutException ||
                error is SocketException ||
                error is http.ClientException) &&
            attempt < retryCount;

        if (!canRetry) rethrow;

        final nextTry = attempt + 2;
        print(
            '⚠️ [ApiService] Network request failed (${error.runtimeType}), retrying ($nextTry/${retryCount + 1})');
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }

    throw StateError('Unhandled request retry state');
  }

  // ============================================================
  // Connectivity
  // ============================================================

  /// Returns true if the server's health endpoint is reachable.
  static Future<bool> isOnline() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // User Profile – Registration & Skills
  // ============================================================

  /// Registers a new volunteer or responder account.
  /// Server endpoint: POST /api/users/register
  static Future<Map<String, dynamic>?> registerUser({
    required String username,
    required String password,
    required String phone,
    required String role,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': username,
              'password': password,
              'phone': phone,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ [ApiService] User registered: $username');
        return data;
      } else {
        print('⚠️ [ApiService] Registration failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [ApiService] registerUser error: $e');
      return null;
    }
  }

  /// Updates a user's profile (skills, resources, etc.).
  /// Server endpoint: PATCH /api/users/{userId}/profile
  static Future<bool> updateUserProfile({
    required int userId,
    required List<String> skills,
    required List<String> resources,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = {
        'skills': skills,
        'resources': resources,
        ...profileData,
      };

      final response = await _requestWithAuth(
        () => http.patch(
          Uri.parse('$baseUrl/users/$userId/profile'),
          headers: headers,
          body: json.encode(body),
        ),
      );

      if (response.statusCode == 200) {
        print('✅ [ApiService] User profile updated: $userId');
        return true;
      } else {
        print('⚠️ [ApiService] Profile update failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ [ApiService] updateUserProfile error: $e');
      return false;
    }
  }

  /// Fetches the authenticated user's saved location anchor and check-in state.
  /// Server endpoint: GET /api/users/me/location
  static Future<Map<String, dynamic>?> getMyLocationAnchor() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/users/me/location'),
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body));
      }

      print(
          '⚠️ [ApiService] getMyLocationAnchor failed: ${response.statusCode}');
    } catch (e) {
      print('⚠️ [ApiService] getMyLocationAnchor error: $e');
    }
    return null;
  }

  /// Saves a volunteer's police-station check-in in the backend.
  /// Server endpoint: PATCH /api/users/me/check-in
  static Future<Map<String, dynamic>?> submitVolunteerCheckIn({
    required String stationName,
    required String parish,
    required double lat,
    required double lon,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.patch(
          Uri.parse('$baseUrl/users/me/check-in'),
          headers: headers,
          body: json.encode({
            'stationName': stationName,
            'parish': parish,
            'lat': lat,
            'lon': lon,
          }),
        ),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body));
      }

      print(
          '⚠️ [ApiService] submitVolunteerCheckIn failed: ${response.statusCode} ${response.body}');
    } catch (e) {
      print('⚠️ [ApiService] submitVolunteerCheckIn error: $e');
    }
    return null;
  }

  // ============================================================
  // Incidents
  // ============================================================

  static Future<List<Incident>> getIncidents() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/incidents'), headers: headers),
      );

      if (response.statusCode == 200) {
        final List jsonList = json.decode(response.body);
        return jsonList.map((e) => Incident.fromJson(e)).toList();
      }
      print(
          '⚠️ [ApiService] Incident fetch returned ${response.statusCode} – using local cache');
    } on TimeoutException catch (e) {
      print('⚠️ [ApiService] Incident fetch timed out – using local cache: $e');
    } on SocketException catch (e) {
      print(
          '⚠️ [ApiService] Incident fetch socket failure – using local cache: $e');
    } on http.ClientException catch (e) {
      print(
          '⚠️ [ApiService] Incident fetch client failure – using local cache: $e');
    } catch (e) {
      print(
          '⚠️ [ApiService] Failed to fetch incidents – using local cache: $e');
    }

    // Fallback: local cache
    final local = _syncService
        .getLocalIncidents()
        .map((e) => Incident.fromJson(e))
        .toList();
    if (local.isNotEmpty) return local;

    // If local cache is also empty and we're in mock mode, return sample data
    // so volunteers/responders have something to see on the map.
    final token = await _authService.getAccessToken();
    if (token != null && token.startsWith('mock_')) {
      print('📦 [ApiService] Returning mock incidents for demo');
      return _mockIncidents();
    }

    return [];
  }

  /// Fetches recommended active incidents near the given coordinates,
  /// sorted by severity (highest first), then distance (nearest first).
  static Future<List<Incident>> getRecommendedTasks(
      double lat, double lon) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/incidents/recommended?lat=$lat&lon=$lon'),
          headers: headers,
        ),
      );

      if (response.statusCode == 200) {
        final List jsonList = json.decode(response.body);
        return jsonList.map((e) => Incident.fromJson(e)).toList();
      }
    } catch (e) {
      print('⚠️ [ApiService] getRecommendedTasks error: $e');
    }
    return [];
  }

  /// Fetch all volunteers/responders for coordinator assignment.
  static Future<List<Map<String, dynamic>>> getVolunteers() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/volunteers/list'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      print('⚠️ [ApiService] getVolunteers error: $e');
    }
    return [];
  }

  /// Assign or reassign a volunteer to an incident (coordinator override).
  static Future<bool> assignIncident(int incidentId, int volunteerId,
      {String status = 'in-progress'}) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/incidents/$incidentId/assign'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: json.encode({
            'volunteerId': volunteerId,
            'status': status,
          }),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] assignIncident error: $e');
      return false;
    }
  }

  /// Sample incidents spread across Jamaica for mock/demo mode.
  static List<Incident> _mockIncidents() {
    final now = DateTime.now();
    return [
      Incident(
        id: 9001,
        type: 'flood',
        lat: 18.0179,
        lon: -76.8099,
        severity: 4,
        description:
            'Flash flooding on Hagley Park Road – multiple vehicles stranded, water rising',
        disasterType: 'flood',
        areaId: 'Kingston',
        status: 'active',
        timestamp: now.subtract(const Duration(hours: 1)),
        lastUpdated: now.subtract(const Duration(minutes: 20)),
        peopleAffected: 35,
      ),
      Incident(
        id: 9002,
        type: 'medical',
        lat: 18.1096,
        lon: -77.2975,
        severity: 5,
        description:
            'Building collapse near Spanish Town – people trapped, urgent medical needed',
        disasterType: 'earthquake',
        areaId: 'St. Catherine',
        status: 'active',
        timestamp: now.subtract(const Duration(minutes: 45)),
        lastUpdated: now.subtract(const Duration(minutes: 10)),
        peopleAffected: 12,
      ),
      Incident(
        id: 9003,
        type: 'fire',
        lat: 18.4762,
        lon: -77.8939,
        severity: 3,
        description:
            'Brush fire spreading towards residential area in Montego Bay',
        disasterType: 'fire',
        areaId: 'St. James',
        status: 'active',
        timestamp: now.subtract(const Duration(hours: 3)),
        lastUpdated: now.subtract(const Duration(hours: 1)),
        peopleAffected: 50,
      ),
      Incident(
        id: 9004,
        type: 'trapped',
        lat: 18.4521,
        lon: -77.5480,
        severity: 5,
        description:
            'Landslide on road to Ocho Rios – 3 cars buried, rescue in progress',
        disasterType: 'landslide',
        areaId: 'St. Ann',
        status: 'in-progress',
        timestamp: now.subtract(const Duration(hours: 2)),
        lastUpdated: now.subtract(const Duration(minutes: 30)),
        peopleAffected: 8,
      ),
      Incident(
        id: 9005,
        type: 'flood',
        lat: 18.2093,
        lon: -77.4961,
        severity: 2,
        description:
            'Minor road flooding in May Pen – traffic diverted, no injuries',
        disasterType: 'flood',
        areaId: 'Clarendon',
        status: 'active',
        timestamp: now.subtract(const Duration(hours: 5)),
        lastUpdated: now.subtract(const Duration(hours: 2)),
        peopleAffected: 0,
      ),
      Incident(
        id: 9006,
        type: 'medical',
        lat: 18.0065,
        lon: -76.7674,
        severity: 4,
        description:
            'Mass casualty incident at Portmore – roof collapse at community centre',
        disasterType: 'structural',
        areaId: 'St. Catherine',
        status: 'active',
        timestamp: now.subtract(const Duration(minutes: 90)),
        lastUpdated: now.subtract(const Duration(minutes: 15)),
        peopleAffected: 20,
      ),
      Incident(
        id: 9007,
        type: 'fire',
        lat: 18.1804,
        lon: -76.3557,
        severity: 3,
        description:
            'Market area fire in Morant Bay – vendors evacuated, fire dept on scene',
        disasterType: 'fire',
        areaId: 'St. Thomas',
        status: 'in-progress',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 15)),
        lastUpdated: now.subtract(const Duration(minutes: 25)),
        peopleAffected: 15,
      ),
    ];
  }

  /// Submits an incident. If offline (or server fails), queues it for later sync.
  static Future<Incident> postIncident(Incident incident) async {
    final idempotencyKey =
        'inc_${DateTime.now().millisecondsSinceEpoch}_${incident.lat}_${incident.lon}';
    final incidentData = {
      ...incident.toJson(),
      'idempotencyKey': idempotencyKey,
    };

    // Always store locally first so it's visible immediately.
    await _syncService.storeIncidentLocally(incidentData);
    print('📦 [ApiService] Stored locally – key: $idempotencyKey');

    final online = await isOnline();

    if (online) {
      try {
        final headers = await _getHeaders();
        final response = await _requestWithAuth(
          () => http.post(
            Uri.parse('$baseUrl/incidents'),
            headers: headers,
            body: json.encode(incidentData),
          ),
        );

        if (response.statusCode == 201) {
          print('✅ [ApiService] Incident posted to server');
          return Incident.fromJson(json.decode(response.body));
        }

        print(
            '⚠️ [ApiService] Server returned ${response.statusCode} – queueing');
      } catch (e) {
        print('⚠️ [ApiService] Post failed – queueing: $e');
      }
    } else {
      print('📴 [ApiService] Offline – incident queued for sync');
    }

    await _syncService.enqueue(
      idempotencyKey: idempotencyKey,
      action: 'CREATE',
      resource: 'incident',
      data: incidentData,
    );

    return incident;
  }

  /// Updates an incident's status. Queues the update if offline or on server error.
  static Future<bool> updateIncidentStatus(int id, String status) async {
    if (id <= 0) {
      print(
          '⚠️ [ApiService] Skipping status update – incident has no server ID (id=$id)');
      // Still update local cache so the UI reflects the change.
      await _syncService.updateLocalIncidentStatus(id, status);
      return false;
    }
    final idempotencyKey =
        'update_${id}_${DateTime.now().millisecondsSinceEpoch}';
    final online = await isOnline();

    if (online) {
      try {
        final headers = await _getHeaders();
        print('🔐 [ApiService] PATCH $baseUrl/incidents/$id → status=$status');
        final response = await _requestWithAuth(
          () => http.patch(
            Uri.parse('$baseUrl/incidents/$id'),
            headers: headers,
            body: json.encode({'status': status}),
          ),
        );

        if (response.statusCode == 200) {
          print('✅ [ApiService] Status updated to "$status" for incident $id');
          // Update local cache to keep it in sync with server.
          await _syncService.updateLocalIncidentStatus(id, status);
          return true;
        }

        print(
            '❌ [ApiService] Server returned ${response.statusCode}: ${response.body}');

        // Queue on any failure so the update is retried when possible.
        await _syncService.enqueue(
          idempotencyKey: idempotencyKey,
          action: 'UPDATE_STATUS',
          resource: 'incident',
          data: {'id': id, 'status': status},
        );
        print(
            '📦 [ApiService] Queued – server returned ${response.statusCode}');

        // Update local cache so the UI reflects the intended status immediately.
        await _syncService.updateLocalIncidentStatus(id, status);
        return false;
      } catch (e) {
        print('⚠️ [ApiService] Network error during PATCH: $e');
        await _syncService.enqueue(
          idempotencyKey: idempotencyKey,
          action: 'UPDATE_STATUS',
          resource: 'incident',
          data: {'id': id, 'status': status},
        );
        print('📦 [ApiService] Queued – network error');
        // Update local cache so the UI reflects the intended status immediately.
        await _syncService.updateLocalIncidentStatus(id, status);
        return false;
      }
    }

    print('📴 [ApiService] Offline – queueing status update');
    await _syncService.enqueue(
      idempotencyKey: idempotencyKey,
      action: 'UPDATE_STATUS',
      resource: 'incident',
      data: {'id': id, 'status': status},
    );
    // Update local cache so the UI reflects the intended status immediately.
    await _syncService.updateLocalIncidentStatus(id, status);
    return false;
  }

  /// Deletes an incident. Queues if offline.
  /// Note: the server's /api/sync handler supports the DELETE action.
  static Future<void> deleteIncident(int id) async {
    final idempotencyKey =
        'delete_${id}_${DateTime.now().millisecondsSinceEpoch}';
    final online = await isOnline();

    if (online) {
      try {
        final headers = await _getHeaders();
        final response = await _requestWithAuth(
          () => http.delete(Uri.parse('$baseUrl/incidents/$id'),
              headers: headers),
        );

        if (response.statusCode == 204 || response.statusCode == 200) {
          print('✅ [ApiService] Incident $id deleted');
          return;
        }
      } catch (e) {
        print('⚠️ [ApiService] Delete failed – queueing: $e');
      }
    }

    await _syncService.enqueue(
      idempotencyKey: idempotencyKey,
      action: 'DELETE',
      resource: 'incident',
      data: {'id': id},
    );
  }

  // ============================================================
  // Resources
  // ============================================================

  static Future<List<Resource>> getResources() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/resources'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List jsonList = json.decode(response.body);
        return jsonList.map((e) => Resource.fromJson(e)).toList();
      }
    } catch (e) {
      print('⚠️ [ApiService] Failed to load resources: $e');
    }
    return [];
  }

  // ============================================================
  // Stats
  // ============================================================

  static Future<Stats> getStats() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/stats'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return Stats.fromJson(json.decode(response.body));
      }
    } catch (e) {
      print('⚠️ [ApiService] Failed to load stats: $e');
    }

    return Stats(
      totalIncidents: 0,
      activeIncidents: 0,
      resolvedIncidents: 0,
      byType: {},
      bySeverity: {},
    );
  }

  // ============================================================
  // Area analysis
  // ============================================================

  static Future<Map<String, dynamic>> getAreaSeverity(String areaId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/severity/$areaId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] Failed to get area severity: $e');
    }
    return {'severityScore': 0, 'incidentCount': 0};
  }

  static Future<Map<String, dynamic>> getAreaResourceEstimate(
      String areaId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/resources/estimate/$areaId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] Failed to get resource estimate: $e');
    }
    return {'needed': {}};
  }

  // ============================================================
  // Police stations (external ArcGIS source)
  // ============================================================

  static Future<List<PoliceStation>> getPoliceStations() async {
    const url =
        'https://services6.arcgis.com/3R3y1KXaPJ9BFnsU/ArcGIS/rest/services/Police_Stations_N/FeatureServer/0/query?where=1%3D1&outFields=NAME,PARISH,TELEPHONE,Address&returnGeometry=true&outSR=4326&f=pjson';
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(_defaultRequestTimeout);
      if (response.statusCode != 200) {
        print(
            '⚠️ [ApiService] Police stations request failed: ${response.statusCode}');
        return [];
      }

      final Map<String, dynamic> payload = json.decode(response.body);
      final features = payload['features'];
      if (features is! List) {
        print('⚠️ [ApiService] Police stations payload missing features list');
        return [];
      }

      final stations = <PoliceStation>[];
      for (final feature in features) {
        if (feature is! Map<String, dynamic>) {
          continue;
        }
        try {
          stations.add(PoliceStation.fromEsriJson(feature));
        } catch (e) {
          print('⚠️ [ApiService] Skipping invalid station feature: $e');
        }
      }
      print('✅ [ApiService] Loaded ${stations.length} police stations');
      return stations;
    } catch (e) {
      print('⚠️ [ApiService] Failed to load police stations: $e');
    }
    return [];
  }

  // ============================================================
  // Health check
  // ============================================================

  static Future<bool> healthCheck() async => isOnline();

  // ============================================================
  // User Profile (Volunteer Profile Enhancement)
  // ============================================================

  static Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/users/$userId/profile'),
            headers: headers),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getUserProfile error: $e');
    }
    return null;
  }

  // ============================================================
  // Broadcast Alerts (#13)
  // ============================================================

  static Future<List<Map<String, dynamic>>> getActiveBroadcasts() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/broadcasts'), headers: headers),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [ApiService] getActiveBroadcasts error: $e');
    }
    return [];
  }

  /// Alias for getActiveBroadcasts (used by alerts_screen.dart)
  static Future<List<Map<String, dynamic>>> getBroadcasts() =>
      getActiveBroadcasts();

  static Future<bool> acknowledgeBroadcast(int alertId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/broadcasts/$alertId/acknowledge'),
          headers: headers,
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] acknowledgeBroadcast error: $e');
      return false;
    }
  }

  // ============================================================
  // Volunteer Stats / Gamification (#3)
  // ============================================================

  static Future<Map<String, dynamic>?> getVolunteerStats(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/volunteers/$userId/stats'),
            headers: headers),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getVolunteerStats error: $e');
    }
    return null;
  }

  static Future<bool> recordTaskCompletion(int userId,
      {double hoursSpent = 1, String? taskType}) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/volunteers/$userId/complete-task'),
          headers: headers,
          body: json.encode({
            'hoursSpent': hoursSpent,
            if (taskType != null) 'taskType': taskType,
          }),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] recordTaskCompletion error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getLeaderboard() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/volunteers/leaderboard'),
            headers: headers),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [ApiService] getLeaderboard error: $e');
    }
    return [];
  }

  // ============================================================
  // Incident Status Transition (#11)
  // ============================================================

  static Future<bool> transitionIncidentStatus(int id, String status) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.patch(
          Uri.parse('$baseUrl/incidents/$id/transition'),
          headers: headers,
          body: json.encode({'status': status}),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] transitionIncidentStatus error: $e');
      return false;
    }
  }

  // ============================================================
  // Volunteer Proximity (#11)
  // ============================================================

  static Future<Map<String, dynamic>?> getUserProximity(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/users/$userId/proximity'),
            headers: headers),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getUserProximity error: $e');
    }
    return null;
  }

  // ============================================================
  // Volunteer Location Updates (#3)
  // ============================================================

  static Future<bool> updateVolunteerLocation(
    double latitude,
    double longitude, {
    double? accuracy,
  }) async {
    try {
      final headers = await _getHeaders();
      final user = await _authService.getUser();
      final userId = user?['id'];
      if (userId == null) return false;
      final response = await _requestWithAuth(
        () => http.patch(
          Uri.parse('$baseUrl/users/$userId/location'),
          headers: headers,
          body: json.encode({
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
          }),
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] updateVolunteerLocation error: $e');
      return false;
    }
  }

  // ============================================================
  // Chat / Messaging (#9)
  // ============================================================

  static Future<List<Map<String, dynamic>>> getIncidentMessages(
      int incidentId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/incidents/$incidentId/messages'),
            headers: headers),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [ApiService] getIncidentMessages error: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> sendIncidentMessage(
      int incidentId, String body) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/incidents/$incidentId/messages'),
          headers: headers,
          body: json.encode({'body': body}),
        ),
      );
      if (response.statusCode == 201) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] sendIncidentMessage error: $e');
    }
    return null;
  }

  static Future<int> getUnreadMessageCount() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/messages/unread'), headers: headers),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['unreadCount'] ?? 0;
      }
    } catch (e) {
      print('⚠️ [ApiService] getUnreadMessageCount error: $e');
    }
    return 0;
  }

  // ============================================================
  // Media Upload (#8)
  // ============================================================

  static Future<Map<String, dynamic>?> getPresignedUrl(
      String filename, String mimeType, int incidentId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/media/presign'),
          headers: headers,
          body: json.encode({
            'filename': filename,
            'mimeType': mimeType,
            'incidentId': incidentId,
          }),
        ),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getPresignedUrl error: $e');
    }
    return null;
  }

  static Future<bool> confirmMediaUpload(int mediaId) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.put(
          Uri.parse('$baseUrl/media/upload/$mediaId'),
          headers: headers,
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ [ApiService] confirmMediaUpload error: $e');
      return false;
    }
  }

  // ============================================================
  // Notifications (#5)
  // ============================================================

  static Future<bool> registerDeviceToken(String token) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/devices/register'),
          headers: headers,
          body: json.encode({'token': token, 'platform': 'android'}),
        ),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('⚠️ [ApiService] registerDeviceToken error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/notifications'), headers: headers),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [ApiService] getNotifications error: $e');
    }
    return [];
  }

  // ============================================================
  // Preparedness Content (#16)
  // ============================================================

  static Future<List<Map<String, dynamic>>> getPreparednessContent() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(Uri.parse('$baseUrl/preparedness'), headers: headers),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [ApiService] getPreparednessContent error: $e');
    }
    return [];
  }

  // ============================================================
  // Analytics (Coordinator Dashboard)
  // ============================================================

  static Future<Map<String, dynamic>> getAnalyticsHealthScore() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/analytics/health-score'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getAnalyticsHealthScore error: $e');
    }
    return {'score': 'red', 'components': {}};
  }

  static Future<Map<String, dynamic>> getAnalyticsResponseTimes(
      {int hours = 24}) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/analytics/response-times?hours=$hours'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getAnalyticsResponseTimes error: $e');
    }
    return {'avgMinutes': 0, 'sampleSize': 0};
  }

  static Future<Map<String, dynamic>> getVolunteerDeployment() async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.get(
          Uri.parse('$baseUrl/analytics/volunteer-deployment'),
          headers: headers,
        ),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('⚠️ [ApiService] getVolunteerDeployment error: $e');
    }
    return {'total': 0, 'available': 0, 'onTask': 0, 'offline': 0};
  }

  // ============================================================
  // Broadcast Creation (Coordinator)
  // ============================================================

  static Future<bool> sendBroadcast({
    required String title,
    required String message,
    required String severity,
    String? targetArea,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await _requestWithAuth(
        () => http.post(
          Uri.parse('$baseUrl/broadcasts/geographic'),
          headers: headers,
          body: json.encode({
            'title': title,
            'message': message,
            'severity': severity,
            if (targetArea != null) 'targetArea': targetArea,
          }),
        ),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('⚠️ [ApiService] sendBroadcast error: $e');
      return false;
    }
  }
}
