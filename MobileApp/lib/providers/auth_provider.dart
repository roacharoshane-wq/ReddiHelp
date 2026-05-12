import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isAuthenticated = false;
  bool _isLoading = true;
  Map<String, dynamic>? _user;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userRole => _user?['role'];
  String? get userPhone => _user?['phone'];
  Map<String, dynamic>? get user => _user;

  // ============================================================
  // Auth state
  // ============================================================

  /// Called on app startup to restore a previously authenticated session.
  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    final accessTokenFuture = _authService.getAccessToken();
    final userFuture = _authService.getUser();

    final token = await accessTokenFuture;
    if (token != null) {
      _user = await userFuture;
      _isAuthenticated = _user != null;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ============================================================
  // Login flows
  // ============================================================

  /// Quick mock login used by the dev/test UI.
  /// Builds a user map locally and persists mock tokens via [AuthService].
  /// This does NOT produce a real JWT – SyncService will skip syncing until
  /// the user authenticates via the real OTP flow.
  Future<bool> mockLogin(String id, String password, String role) async {
    await Future.delayed(const Duration(seconds: 1));

    _user = {
      'id': DateTime.now().millisecondsSinceEpoch % 10000,
      'username': id,
      'role': role,
      // Volunteers must complete their profile before they appear as available.
      'profileCompleted': role != 'volunteer',
    };

    await _authService.saveMockUser(_user!);

    _isAuthenticated = true;
    notifyListeners();
    return true;
  }

  /// OTP request – step 1 of the victim login flow.
  Future<bool> requestOtp(String phone) async {
    return _authService.requestOtp(phone);
  }

  /// OTP verification – step 2 of the victim login flow.
  /// On success, stores the returned JWT and user object.
  Future<bool> verifyOtp(String phone, String otp, String role) async {
    final data = await _authService.verifyOtp(phone, otp, role);
    if (data != null) {
      _user = data['user'];
      _user!['profileCompleted'] = true; // victims skip profile setup
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Username / password login for non-victim roles (coordinator, responder, volunteer).
  /// Delegates to [AuthService.login]; in mock mode this still generates a
  /// mock token – set [AuthService._mockMode] = false for real JWT auth.
  /// [selectedRole] is the role chosen on the login screen so the service can
  /// reject credentials that belong to a different role.
  Future<bool> login(String username, String password,
      {required String selectedRole}) async {
    final data = await _authService.login(username, password, selectedRole);
    if (data != null) {
      _user = data['user'];
      final skills = List<String>.from(_user?['skills'] ?? const []);
      if ((_user?['role'] == 'volunteer' || _user?['role'] == 'responder') &&
          skills.isNotEmpty) {
        _user!['profileCompleted'] = true;
      }
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Create a new account for volunteer or responder.
  /// On success, user is logged in and must complete their profile.
  Future<bool> register(
    String username,
    String password,
    String phone,
    String role,
    List<String> skills,
  ) async {
    final data = await _authService.register(
      username,
      password,
      phone,
      role,
      skills,
    );
    if (data != null) {
      _user = data['user'];
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }
    return false;
  }

  // ============================================================
  // Profile management
  // ============================================================

  /// Merges [profileData] into the current user and marks the profile complete.
  /// Used after a volunteer or responder fills in their skills / resource form.
  Future<void> updateUserProfile(Map<String, dynamic> profileData) async {
    if (_user != null) {
      _user!.addAll(profileData);
      _user!['profileCompleted'] = true;
      await _authService.updateUser(_user!);
      notifyListeners();
    }
  }

  /// Legacy alias for backward compatibility with VolunteerProfileScreen.
  Future<void> updateVolunteerProfile(Map<String, dynamic> profileData) async {
    await updateUserProfile(profileData);
  }

  /// Returns the current user's skills, or an empty list if not set.
  List<String> get skills {
    if (_user == null || _user!['skills'] == null) return [];
    return List<String>.from(_user!['skills']);
  }

  /// Returns the current user's resources, or an empty list if not set.
  List<String> get resources {
    if (_user == null || _user!['resources'] == null) return [];
    return List<String>.from(_user!['resources']);
  }

  // ============================================================
  // Logout
  // ============================================================

  Future<void> logout() async {
    await _authService.logout();
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
