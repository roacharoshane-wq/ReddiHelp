import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  Future<void> init() async {
    if (_initialized) return;

    // Request permission (iOS/macOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // For EVACUATION_ALERT
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get FCM token
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        print('📱 [FCM] Token obtained: ${_fcmToken!.substring(0, 20)}...');
        await _registerTokenWithBackend(_fcmToken!);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        await _registerTokenWithBackend(newToken);
      });

      // Foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Background/terminated message tap handler
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Check if app was opened from a notification (cold start)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      _initialized = true;
      print('✅ [FCM] Notification service initialized');
    } else {
      print('⚠️ [FCM] Notification permission denied');
    }
  }

  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final accessToken = await AuthService().getAccessToken();
      if (accessToken == null) return;

      await http.post(
        Uri.parse('${ApiService.baseUrl}/devices/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: json.encode({
          'fcmToken': token,
          'platform': 'android', // Will be overridden for iOS
        }),
      );
      print('✅ [FCM] Token registered with backend');
    } catch (e) {
      print('⚠️ [FCM] Failed to register token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type'] ?? '';
    final title = message.notification?.title ?? 'ReddiHelp';
    final body = message.notification?.body ?? '';

    print('📬 [FCM] Foreground message: $type — $title');

    // EVACUATION_ALERT must show full-screen modal — handled by the app's
    // broadcast listener. Other categories are shown as snackbar/banner.
    if (type == 'EVACUATION_ALERT') {
      _onEvacuationAlert(message);
    }

    // Notify listeners (the app's UI can react via this callback)
    if (_onMessageCallback != null) {
      _onMessageCallback!(type, title, body, message.data);
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    final type = message.data['type'] ?? '';
    print('📬 [FCM] Message tapped: $type');
    if (_onMessageTapCallback != null) {
      _onMessageTapCallback!(type, message.data);
    }
  }

  void _onEvacuationAlert(RemoteMessage message) {
    // This is picked up by the main app to show a full-screen modal
    if (_onEvacuationCallback != null) {
      _onEvacuationCallback!(
        message.notification?.body ??
            message.data['message'] ??
            'Emergency evacuation alert',
      );
    }
  }

  // Callbacks for the app to register
  void Function(
          String type, String title, String body, Map<String, dynamic> data)?
      _onMessageCallback;
  void Function(String type, Map<String, dynamic> data)? _onMessageTapCallback;
  void Function(String message)? _onEvacuationCallback;

  void setOnMessageCallback(
      void Function(
              String type, String title, String body, Map<String, dynamic> data)
          callback) {
    _onMessageCallback = callback;
  }

  void setOnMessageTapCallback(
      void Function(String type, Map<String, dynamic> data) callback) {
    _onMessageTapCallback = callback;
  }

  void setOnEvacuationCallback(void Function(String message) callback) {
    _onEvacuationCallback = callback;
  }

  // Subscribe to topic for geographic broadcasts
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }
}
