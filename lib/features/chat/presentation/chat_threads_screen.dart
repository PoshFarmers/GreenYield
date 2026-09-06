import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/avatar_image.dart';
import '../../../models/chat_models.dart';
import '../../../models/profile.dart';
import '../application/chat_providers.dart';
import 'chat_screen.dart';

/// Central `chat_threads_screen.dart` — one Chat tab shared by every
/// role's nav shell. Lists every active thread the signed-in user is
/// part of, with avatar, recipient name, a dynamic role badge, latest
/// message snippet, relative timestamp, and an unread indicator. Backed
/// by [chatThreadsProvider], which stays live via Supabase Realtime.
class ChatThreadsScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const ChatThreadsScreen({super.key, required this.profile});

  @override
  ConsumerState<ChatThreadsScreen> createState() => _ChatThreadsScreenState();
}

class _ChatThreadsScreenState extends ConsumerState<ChatThreadsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(chatThreadsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('chat_title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'search_messages'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: threadsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('failed_to_load_chats'.tr()),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(chatThreadsProvider),
                        child: Text('retry'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
              data: (threads) {
                final filtered = _query.isEmpty
                    ? threads
                    : threads
                          .where(
                            (t) => t.otherName.toLowerCase().contains(_query),
                          )
                          .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'no_conversations_title'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'no_conversations_subtitle'.tr(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _ThreadTile(
                    thread: filtered[index],
                    profile: widget.profile,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final ChatThread thread;
  final Profile profile;

  const _ThreadTile({required this.thread, required this.profile});

  String _roleLabel() => switch (thread.otherRole) {
    ChatRole.farmer => 'role_farmer'.tr(),
    ChatRole.buyer => 'role_buyer'.tr(),
    ChatRole.driver => 'role_driver'.tr(),
  };

  Color _roleColor(BuildContext context) => switch (thread.otherRole) {
    ChatRole.farmer => Theme.of(context).colorScheme.primary,
    ChatRole.buyer => Colors.blueGrey,
    ChatRole.driver => Colors.deepOrange,
  };

  String _relativeTimestamp() {
    final at = thread.lastMessageAt ?? thread.updatedAt;
    final now = DateTime.now();
    final isToday =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        at.year == yesterday.year &&
        at.month == yesterday.month &&
        at.day == yesterday.day;

    if (isToday) {
      final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
      final minute = at.minute.toString().padLeft(2, '0');
      final period = at.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }
    if (isYesterday) return 'yesterday'.tr();
    return '${at.month}/${at.day}/${at.year % 100}';
  }

  @override
  Widget build(BuildContext context) {
    final snippet = thread.lastMessageText ?? 'chat_photo'.tr();

    return Material(
      color: thread.hasUnread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
          : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarImage(path: thread.otherAvatarUrl, radius: 26),
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _roleColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _roleLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          thread.otherName,
          style: TextStyle(
            fontWeight: thread.hasUnread ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          thread.isLastMessageFromMe ? '${'you'.tr()}: $snippet' : snippet,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: thread.hasUnread
              ? const TextStyle(fontWeight: FontWeight.w600)
              : TextStyle(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.6),
                ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _relativeTimestamp(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            if (thread.hasUnread)
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                child: Text(
                  thread.unreadCount > 99 ? '99+' : '${thread.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: thread.conversationId,
                otherName: thread.otherName,
                otherAvatarUrl: thread.otherAvatarUrl,
                currentUserId: profile.id,
              ),
            ),
          );
        },
      ),
    );
  }
}
