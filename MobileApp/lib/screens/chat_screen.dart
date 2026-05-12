import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import 'preparedness_guide_screen.dart';

class ChatScreen extends StatefulWidget {
  final int incidentId;
  final String incidentType;

  const ChatScreen({
    super.key,
    required this.incidentId,
    required this.incidentType,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  bool _showTemplates = false;
  int? _currentUserId;
  String? _currentUserRole;
  Timer? _typingTimer;
  bool _isTyping = false;
  Timer? _markReadTimer;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _currentUserId = auth.user?['id'];
    _currentUserRole = auth.userRole;

    // Connect and subscribe
    await _chatService.connect();
    _chatService.subscribeToIncident(widget.incidentId);

    // Add listener for real-time messages
    _chatService.addListener(_onChatUpdate);

    // Load history
    final messages = await _chatService.getMessages(widget.incidentId);
    await _chatService.markAsRead(widget.incidentId);

    // Load templates for coordinators
    if (_currentUserRole == 'coordinator') {
      _templates = await _chatService.getTemplates();
    }

    if (mounted) {
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  void _onChatUpdate() {
    if (!mounted) return;
    final messages = _chatService.getCachedMessages(widget.incidentId);
    setState(() => _messages = List.from(messages));
    // Debounce markAsRead to avoid spamming the server
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _chatService.markAsRead(widget.incidentId);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    await _chatService.sendMessage(widget.incidentId, text);
  }

  void _sendTemplate(Map<String, dynamic> template) {
    _chatService.sendMessage(widget.incidentId, template['text'],
        messageType: 'template');
    setState(() => _showTemplates = false);
  }

  void _onTextChanged(String text) {
    if (!_isTyping) {
      _isTyping = true;
      _chatService.sendTypingIndicator(widget.incidentId);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
    });
  }

  @override
  void dispose() {
    _chatService.removeListener(_onChatUpdate);
    _chatService.unsubscribeFromIncident(widget.incidentId);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _markReadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Incident #${widget.incidentId}'),
            Text(
              widget.incidentType.replaceAll('_', ' ').toUpperCase(),
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (_currentUserRole == 'coordinator')
            IconButton(
              icon: Icon(
                  _showTemplates ? Icons.close : Icons.quick_contacts_mail),
              onPressed: () => setState(() => _showTemplates = !_showTemplates),
              tooltip: 'Quick Replies',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status
          if (!_chatService.isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              color: Colors.orange[100],
              child: const Text(
                'Reconnecting...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),

          // Quick-reply templates
          if (_showTemplates && _templates.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.grey[100],
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.length,
                itemBuilder: (ctx, i) {
                  final t = _templates[i];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ActionChip(
                      label: Text(t['label'] ?? '',
                          style: const TextStyle(fontSize: 12)),
                      onPressed: () => _sendTemplate(t),
                      backgroundColor: Colors.teal[50],
                    ),
                  );
                },
              ),
            ),

          // Messages
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('No messages yet',
                                style: TextStyle(color: Colors.grey[600])),
                            const SizedBox(height: 4),
                            Text('Send a message to start the conversation',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) =>
                            _buildMessageBubble(_messages[i]),
                      ),
          ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      onChanged: _onTextChanged,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.senderId == _currentUserId;
    final isSystem = message.isSystem;

    if (isSystem) {
      final hasGuideLink = message.content.contains('/api/preparedness/');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic),
                ),
              ),
              if (hasGuideLink) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            const PreparednessGuideScreen(victimMode: true)));
                  },
                  child: const Text('Open full guidance'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender role label
            if (!isMe && message.senderRole != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  _roleLabel(message.senderRole!),
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.teal : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white70 : Colors.grey[500],
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.read ? Icons.done_all : Icons.done,
                          size: 14,
                          color: message.read
                              ? Colors.lightBlueAccent
                              : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'coordinator':
        return '📋 Coordinator';
      case 'volunteer':
        return '🤝 Volunteer';
      case 'responder':
        return '🚨 Responder';
      default:
        return '👤 User';
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
