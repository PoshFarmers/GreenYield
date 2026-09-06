import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/chat_models.dart';
import '../chat_service.dart';

final chatServiceProvider = Provider<ChatService>((ref) => const ChatService());

/// Live thread list backing `chat_threads_screen.dart`.
final chatThreadsProvider = StreamProvider<List<ChatThread>>((ref) {
  return ref.watch(chatServiceProvider).watchChatThreads();
});

/// Live count of distinct threads with unread messages — feeds the
/// yellow badge on every role's Chat nav tab.
final unreadConversationCountProvider = StreamProvider<int>((ref) {
  return ref.watch(chatServiceProvider).getUnreadConversationCountStream();
});

/// Live message stream for one conversation room.
final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatServiceProvider).streamMessages(conversationId);
});

/// Live read-cursor for the other participant in a conversation, used
/// to render "seen" checkmarks on the caller's own messages.
final peerLastReadAtProvider = StreamProvider.family<DateTime?, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatServiceProvider).streamPeerLastReadAt(conversationId);
});
