import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/chat_message.dart';
import 'api_service.dart';
import 'auth_service.dart';

class ChatService extends ChangeNotifier {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  IO.Socket? _socket;
  final Map<int, List<ChatMessage>> _messageCache = {};
  final Map<int, int> _unreadCounts = {};
  bool _connected = false;

  bool get isConnected => _connected;
  Map<int, int> get unreadCounts => Map.unmodifiable(_unreadCounts);

  /// Connect to Socket.io for real-time chat.
  Future<void> connect() async {
    if (_socket != null && _connected) return;

    final token = await AuthService().getAccessToken();
    final baseUrl = ApiService.socketBaseUrl;

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token ?? ''})
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      print('🔌 [Chat] Socket.io connected');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      notifyListeners();
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        final msg = ChatMessage.fromJson(Map<String, dynamic>.from(data));
        _addMessageToCache(msg);
        _updateUnreadCount(msg.incidentId);
        notifyListeners();
      }
    });

    _socket!.connect();
  }

  void _addMessageToCache(ChatMessage msg) {
    _messageCache.putIfAbsent(msg.incidentId, () => []);
    // Avoid duplicates
    if (!_messageCache[msg.incidentId]!.any((m) => m.id == msg.id)) {
      _messageCache[msg.incidentId]!.add(msg);
    }
  }

  void _updateUnreadCount(int incidentId) {
    _unreadCounts[incidentId] = (_unreadCounts[incidentId] ?? 0) + 1;
  }

  /// Subscribe to a specific incident's chat room.
  void subscribeToIncident(int incidentId) {
    _socket?.emit('subscribe:incident', incidentId);
  }

  /// Unsubscribe from an incident's chat room.
  void unsubscribeFromIncident(int incidentId) {
    _socket?.emit('unsubscribe:incident', incidentId);
  }

  /// Fetch message history for an incident from the backend.
  Future<List<ChatMessage>> getMessages(int incidentId,
      {int limit = 50}) async {
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse(
            '${ApiService.baseUrl}/incidents/$incidentId/messages?limit=$limit'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final messages = data.map((m) => ChatMessage.fromJson(m)).toList();
        _messageCache[incidentId] = messages;
        notifyListeners();
        return messages;
      }
    } catch (e) {
      print('⚠️ [Chat] Failed to load messages: $e');
    }

    // Return cached if available
    return _messageCache[incidentId] ?? [];
  }

  /// Send a message via Socket.io (real-time) with HTTP fallback.
  Future<bool> sendMessage(int incidentId, String content,
      {String messageType = 'text'}) async {
    if (_socket != null && _connected) {
      _socket!.emit('chat:send', {
        'incidentId': incidentId,
        'content': content,
        'messageType': messageType,
      });
      return true;
    }

    // Fallback: HTTP POST
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/incidents/$incidentId/messages'),
        headers: headers,
        body: json.encode({
          'content': content,
          'messageType': messageType,
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('⚠️ [Chat] Failed to send message: $e');
      return false;
    }
  }

  /// Send typing indicator.
  void sendTypingIndicator(int incidentId) {
    _socket?.emit('chat:typing', {'incidentId': incidentId});
  }

  /// Mark messages as read for an incident.
  Future<void> markAsRead(int incidentId) async {
    // Skip for invalid/local-only incident IDs
    if (incidentId <= 0) return;

    _unreadCounts[incidentId] = 0;
    notifyListeners();

    // Skip network call if offline
    final online = await ApiService.isOnline();
    if (!online) return;

    try {
      final headers = await ApiService.getHeaders();
      await http
          .patch(
            Uri.parse(
                '${ApiService.baseUrl}/incidents/$incidentId/messages/read'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      print('⚠️ [Chat] Failed to mark as read: $e');
    }
  }

  /// Fetch unread counts for all incidents.
  Future<void> loadUnreadCounts() async {
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/messages/unread'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _unreadCounts.clear();
        data.forEach((k, v) {
          _unreadCounts[int.parse(k)] = v as int;
        });
        notifyListeners();
      }
    } catch (e) {
      print('⚠️ [Chat] Failed to load unread counts: $e');
    }
  }

  /// Fetch quick-reply templates.
  Future<List<Map<String, dynamic>>> getTemplates() async {
    try {
      final headers = await ApiService.getHeaders();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/chat/templates'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('⚠️ [Chat] Failed to load templates: $e');
    }
    return [];
  }

  /// Get cached messages for an incident.
  List<ChatMessage> getCachedMessages(int incidentId) {
    return _messageCache[incidentId] ?? [];
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }
}
