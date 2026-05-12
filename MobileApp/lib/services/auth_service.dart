import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

// ============================================================
// AuthService
//
// Victim OTP login uses mock mode by default so local testing can skip
// Firebase integration. Non-victim username/password auth remains real
// unless AUTH_MOCK_MODE=true is enabled explicitly.
// ============================================================

class AuthService {
  // ── Toggle this to switch volunteer/responder/coordinator auth mode ──
  static const bool _mockMode =
      bool.fromEnvironment('AUTH_MOCK_MODE', defaultValue: false);

  // ── Toggle this to keep victim OTP mocked for local development ──
  static const bool _mockOtpMode =
      bool.fromEnvironment('AUTH_OTP_MOCK_MODE', defaultValue: true);

  static String get _baseUrl => '${AppConfig.apiBaseUrl}/auth';

  static const String _accessTokenKey = 'accessToken';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _userKey = 'user';
  static const String _mockUsersKey = 'mockUsers';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  List<String> _defaultSkillsForRole(String role) {
    if (role == 'volunteer') {
      return ['First Aid / CPR', 'Logistics / Transport'];
    }
    if (role == 'responder') {
      return ['Incident Command', 'Search & Rescue'];
    }
    return const [];
  }

  // ============================================================
  // Token storage helpers (shared by both modes)
  // ============================================================

  Future<void> saveTokens(
    String accessToken,
    String refreshToken,
    Map<String, dynamic> user,
  ) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _userKey, value: json.encode(user));
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  Future<Map<String, dynamic>?> getUser() async {
    final userStr = await _storage.read(key: _userKey);
    if (userStr == null) return null;
    return json.decode(userStr);
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    await _storage.write(key: _userKey, value: json.encode(user));
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userKey);
  }

  Future<List<Map<String, dynamic>>> _readMockUsers() async {
    final raw = await _storage.read(key: _mockUsersKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = json.decode(raw);
    if (decoded is! List) return [];
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _writeMockUsers(List<Map<String, dynamic>> users) async {
    await _storage.write(key: _mockUsersKey, value: json.encode(users));
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null;
  }

  Future<void> logout() async {
    await clearTokens();
  }

  /// Clears all mock user accounts from secure storage.
  /// Call once after fixing role-assignment bugs to wipe stale data.
  Future<void> clearMockUsers() async {
    await _storage.delete(key: _mockUsersKey);
  }

  /// Convenience method used by [AuthProvider.mockLogin] to persist a locally
  /// constructed user object with mock tokens. Only meaningful when [_mockMode]
  /// is true – real login flows use [verifyOtp] / [login] instead.
  Future<void> saveMockUser(Map<String, dynamic> user) async {
    final accessToken = 'mock_access_${DateTime.now().millisecondsSinceEpoch}';
    final refreshToken =
        'mock_refresh_${DateTime.now().millisecondsSinceEpoch}';
    await saveTokens(accessToken, refreshToken, user);
  }

  // ============================================================
  // OTP request (Firebase Phone Auth)
  // ============================================================

  Future<bool> requestOtp(String phone) async {
    if (_mockOtpMode) {
      await Future.delayed(const Duration(seconds: 1));
      print('📱 [MOCK OTP] OTP requested for $phone');
      return true;
    }

    print(
        '❌ Firebase auth not configured. Enable AUTH_OTP_MOCK_MODE or add firebase_auth.');
    return false;
  }

  // ============================================================
  // OTP verification (Firebase Phone Auth)
  // ============================================================

  Future<Map<String, dynamic>?> verifyOtp(
    String phone,
    String otp,
    String role,
  ) async {
    if (_mockOtpMode) {
      await Future.delayed(const Duration(seconds: 1));

      if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
        print('❌ [MOCK OTP] Invalid OTP format');
        return null;
      }

      print('✅ [MOCK OTP] OTP accepted for $phone with role $role');

      final accessToken =
          'mock_access_${DateTime.now().millisecondsSinceEpoch}';
      final refreshToken =
          'mock_refresh_${DateTime.now().millisecondsSinceEpoch}';
      final user = {
        'id': DateTime.now().millisecondsSinceEpoch % 10000,
        'phone': phone,
        'role': role,
        'profileCompleted': true,
      };

      await saveTokens(accessToken, refreshToken, user);
      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user
      };
    }

    print(
        '❌ Firebase auth not configured. Enable mock mode or add firebase_auth.');
    return null;
  }

  // ============================================================
  // Registration – new account creation (volunteers & responders)
  // ============================================================

  /// Creates a new volunteer or responder account with username, password, and phone.
  /// On success, logs the user in immediately.
  Future<Map<String, dynamic>?> register(
    String username,
    String password,
    String phone,
    String role,
    List<String> skills,
  ) async {
    if (_mockMode) {
      await Future.delayed(const Duration(seconds: 1));
      print('📝 [MOCK] Creating account: $username ($role)');

      if (role != 'volunteer' && role != 'responder') {
        print('❌ [MOCK] Invalid role for registration: $role');
        return null;
      }

      final users = await _readMockUsers();
      final usernameTaken = users.any(
        (u) =>
            (u['username'] ?? '').toString().toLowerCase() ==
            username.toLowerCase(),
      );
      if (usernameTaken) {
        print('❌ [MOCK] Username already exists: $username');
        return null;
      }

      // Mock registration – create tokens and user
      final accessToken =
          'mock_access_${DateTime.now().millisecondsSinceEpoch}';
      final refreshToken =
          'mock_refresh_${DateTime.now().millisecondsSinceEpoch}';
      final user = {
        'id': DateTime.now().millisecondsSinceEpoch % 10000,
        'username': username,
        'phone': phone,
        'role': role,
        'profileCompleted': true,
        'skills': skills.isEmpty ? _defaultSkillsForRole(role) : skills,
        'resources': [],
      };

      users.add({
        ...user,
        'password': password,
      });
      await _writeMockUsers(users);

      await saveTokens(accessToken, refreshToken, user);
      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user
      };
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'username': username,
              'password': password,
              'phone': phone,
              'role': role,
              'skills': skills,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        await saveTokens(
            data['accessToken'], data['refreshToken'], data['user']);
        print('✅ Account created and logged in: $username');
        return data;
      }
      print('❌ Registration failed: ${response.body}');
      return null;
    } catch (e) {
      print('❌ register error: $e');
      return null;
    }
  }

  // ============================================================
  // Username / password login (non-victim roles)
  // ============================================================

  Future<Map<String, dynamic>?> login(
      String username, String password, String selectedRole) async {
    if (_mockMode) {
      await Future.delayed(const Duration(seconds: 1));
      print(
          '📱 [MOCK] Login attempt for $username (selected role: $selectedRole)');

      final users = await _readMockUsers();

      // Check if a user with this username already exists in mock storage
      final existingUser = users.cast<Map<String, dynamic>?>().firstWhere(
            (u) =>
                (u?['username'] ?? '').toString().toLowerCase() ==
                username.toLowerCase(),
            orElse: () => null,
          );

      Map<String, dynamic>? userRecord;

      if (existingUser != null) {
        // User exists – validate password
        if ((existingUser['password'] ?? '').toString() != password) {
          print('❌ [MOCK] Invalid password for $username');
          return null;
        }
        // User exists – validate role matches what was selected on login screen
        final storedRole = (existingUser['role'] ?? '').toString();
        if (storedRole != selectedRole) {
          print(
              '❌ [MOCK] Role mismatch: account is $storedRole but tried to log in as $selectedRole');
          return null;
        }
        userRecord = existingUser;
      } else {
        print('❌ [MOCK] Invalid username or password for $username');
        return null;
      }

      final role = (userRecord['role'] ?? 'coordinator').toString();
      final savedSkills = List<String>.from(userRecord['skills'] ?? const []);
      final effectiveSkills =
          savedSkills.isEmpty ? _defaultSkillsForRole(role) : savedSkills;

      final accessToken =
          'mock_access_${DateTime.now().millisecondsSinceEpoch}';
      final refreshToken =
          'mock_refresh_${DateTime.now().millisecondsSinceEpoch}';
      final user = {
        'id':
            userRecord['id'] ?? (DateTime.now().millisecondsSinceEpoch % 10000),
        'username': username,
        'role': role,
        'phone': userRecord['phone'],
        'profileCompleted': role == 'coordinator' || effectiveSkills.isNotEmpty,
        'skills': effectiveSkills,
        'resources': List<String>.from(userRecord['resources'] ?? const []),
      };

      await saveTokens(accessToken, refreshToken, user);
      return {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'user': user
      };
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Validate that the server-returned role matches the selected role
        final serverRole = (data['user']?['role'] ?? '').toString();
        if (serverRole != selectedRole) {
          print(
              '❌ Role mismatch: server says $serverRole but selected $selectedRole');
          return null;
        }
        await saveTokens(
            data['accessToken'], data['refreshToken'], data['user']);
        return data;
      }
      print('❌ Login failed: ${response.body}');
      return null;
    } catch (e) {
      print('❌ login error: $e');
      return null;
    }
  }

  // ============================================================
  // Token refresh
  // ============================================================

  Future<String?> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return null;

    if (_mockMode || _mockOtpMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      // Still returns a mock token – SyncService will detect the prefix and skip sync.
      final newAccessToken =
          'mock_access_${DateTime.now().millisecondsSinceEpoch}';
      final user = await getUser();
      await saveTokens(newAccessToken, refreshToken, user ?? {});
      print('🔄 [MOCK] Token refreshed (mock)');
      return newAccessToken;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newAccessToken = data['accessToken'];
        final user = await getUser();
        await saveTokens(newAccessToken, refreshToken, user ?? {});
        print('🔄 Token refreshed successfully');
        return newAccessToken;
      }
      print('❌ Refresh failed: ${response.body}');
      return null;
    } catch (e) {
      print('❌ refreshAccessToken error: $e');
      return null;
    }
  }
}
