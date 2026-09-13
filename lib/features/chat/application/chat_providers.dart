import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_models.dart';
import '../chat_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) => const ChatService());

/// Live thread list for the currently active role.
final chatThreadsProvider = StreamProvider.family<List<ChatThread>, String>((
  ref,
  activeRole,
) {
  return ref.watch(chatServiceProvider).watchChatThreads(activeRole);
});

/// Live count of unread conversation threads for the currently active role.
final unreadConversationCountProvider = StreamProvider.family<int, String>((
  ref,
  activeRole,
) {
  return ref
      .watch(chatServiceProvider)
      .getUnreadConversationCountStream(activeRole);
});

/// Live message stream for one conversation room.
final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatServiceProvider).streamMessages(conversationId);
});

/// Live read cursor for the other participant in a conversation.
final peerLastReadAtProvider = StreamProvider.family<DateTime?, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatServiceProvider).streamPeerLastReadAt(conversationId);
});
