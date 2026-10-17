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

/// Number of threads with unread messages, derived from the thread list so
/// there is a single source of truth (no second RPC / realtime stream).
/// Being a plain [Provider], listeners only rebuild when the count changes.
final unreadConversationCountProvider = Provider.family<int, String>((
  ref,
  activeRole,
) {
  final threads = ref
      .watch(chatThreadsProvider(activeRole))
      .when(
        skipLoadingOnReload: true,
        skipError: true,
        data: (t) => t,
        loading: () => const <ChatThread>[],
        error: (_, _) => const <ChatThread>[],
      );
  return threads.where((t) => t.hasUnread).length;
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
