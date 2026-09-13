/// Role tag used for the dynamic role badge on a thread ('farmer' |
/// 'buyer' | 'driver'), and for picking which role a new
/// conversation's participant rows are stamped with.
enum ChatRole {
  buyer,
  farmer,
  driver;

  static ChatRole fromString(String value) =>
      ChatRole.values.firstWhere((r) => r.name == value);
}

/// One row of the Chat tab thread list — backed by the
/// `get_chat_threads()` RPC, which already resolves "the other
/// participant" (from their own snapshot on `conversation_participant`)
/// and the latest message server-side.
class ChatThread {
  final String conversationId;
  final String otherUserId;
  final ChatRole otherRole;
  final String otherName;
  final String? otherAvatarUrl;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final bool isLastMessageFromMe;
  final bool hasUnread;
  final int unreadCount;
  final DateTime updatedAt;

  const ChatThread({
    required this.conversationId,
    required this.otherUserId,
    required this.otherRole,
    required this.otherName,
    this.otherAvatarUrl,
    this.lastMessageText,
    this.lastMessageAt,
    required this.isLastMessageFromMe,
    required this.hasUnread,
    this.unreadCount = 0,
    required this.updatedAt,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map) => ChatThread(
    conversationId: map['conversation_id'] as String,
    otherUserId: map['other_user_id'] as String,
    otherRole: ChatRole.fromString(map['other_role'] as String),
    otherName: (map['other_name'] as String?) ?? 'Unknown',
    otherAvatarUrl: map['other_avatar_url'] as String?,
    lastMessageText: map['last_message_text'] as String?,
    lastMessageAt: map['last_message_at'] == null
        ? null
        : DateTime.parse(map['last_message_at'] as String).toLocal(),
    isLastMessageFromMe: map['is_last_from_me'] as bool? ?? false,
    hasUnread: map['has_unread'] as bool? ?? false,
    unreadCount: map['unread_count'] as int? ?? 0,
    updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
  );
}

/// One message bubble in `chat_screen.dart`, backed directly by a row
/// of the `message` table (this feature streams the raw table via
/// Supabase Realtime rather than going through an RPC).
///
/// There's no per-message `is_read` flag on this schema — "seen" is
/// derived by the UI by comparing [createdAt] against the other
/// participant's `last_read_at` cursor (see `ChatService.streamPeerLastReadAt`).
class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final String? attachmentUrl;
  final String? attachmentType; // e.g. 'image'
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.body,
    this.attachmentUrl,
    this.attachmentType,
    required this.createdAt,
  });

  bool get isImage => attachmentType == 'image' && attachmentUrl != null;

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as String,
    conversationId: map['conversation_id'] as String,
    senderId: map['sender_id'] as String,
    body: map['body'] as String?,
    attachmentUrl: map['attachment_url'] as String?,
    attachmentType: map['attachment_type'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
  );
}
