class ChatMessage {
  final int id;
  final int incidentId;
  final int senderId;
  final String content;
  final String messageType; // 'text', 'system', 'template'
  final String? senderRole;
  final String? senderPhone;
  final bool delivered;
  final bool read;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.incidentId,
    required this.senderId,
    required this.content,
    this.messageType = 'text',
    this.senderRole,
    this.senderPhone,
    this.delivered = false,
    this.read = false,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? 0,
      incidentId: json['incident_id'] ?? json['incidentId'] ?? 0,
      senderId: json['sender_id'] ?? json['senderId'] ?? 0,
      content: json['content'] ?? '',
      messageType: json['message_type'] ?? json['messageType'] ?? 'text',
      senderRole: json['sender_role'] ?? json['senderRole'],
      senderPhone: json['sender_phone'] ?? json['senderPhone'],
      delivered: json['delivered'] ?? false,
      read: json['read'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : (json['createdAt'] != null
              ? DateTime.parse(json['createdAt'].toString())
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() => {
        'incident_id': incidentId,
        'content': content,
        'message_type': messageType,
      };

  bool get isSystem => messageType == 'system';
}
