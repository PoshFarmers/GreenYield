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

/// A chip in the role-based filter bar. `all` and `unread` are always
/// present; `role` chips are derived from the signed-in user's
/// [Profile.activeRole] so a Buyer sees Farmers/Drivers, a Farmer sees
/// Buyers/Drivers, and a Driver sees Farmers/Buyers.
sealed class _ThreadFilter {
  const _ThreadFilter();

  const factory _ThreadFilter.all() = _AllFilter;
  const factory _ThreadFilter.unread() = _UnreadFilter;
  const factory _ThreadFilter.role(ChatRole role) = _RoleFilter;

  String label() => switch (this) {
    _AllFilter() => 'filter_all'.tr(),
    _UnreadFilter() => 'filter_unread'.tr(),
    _RoleFilter(role: final role) => switch (role) {
      ChatRole.farmer => 'role_farmers'.tr(),
      ChatRole.buyer => 'role_buyers'.tr(),
      ChatRole.driver => 'role_drivers'.tr(),
    },
  };

  bool matches(ChatThread thread) => switch (this) {
    _AllFilter() => true,
    _UnreadFilter() => thread.hasUnread,
    _RoleFilter(role: final role) => thread.otherRole == role,
  };

  @override
  bool operator ==(Object other) => switch ((this, other)) {
    (_AllFilter(), _AllFilter()) => true,
    (_UnreadFilter(), _UnreadFilter()) => true,
    (_RoleFilter(role: final a), _RoleFilter(role: final b)) => a == b,
    _ => false,
  };

  @override
  int get hashCode => switch (this) {
    _AllFilter() => 0,
    _UnreadFilter() => 1,
    _RoleFilter(role: final role) => role.hashCode,
  };
}

class _AllFilter extends _ThreadFilter {
  const _AllFilter();
}

class _UnreadFilter extends _ThreadFilter {
  const _UnreadFilter();
}

class _RoleFilter extends _ThreadFilter {
  final ChatRole role;
  const _RoleFilter(this.role);
}

/// Maps the signed-in user's active role to the two "other role" chips
/// they should see, in display order, after the fixed All/Unread chips.
List<ChatRole> _peerRolesFor(String? activeRole) => switch (activeRole) {
  'buyer' => const [ChatRole.farmer, ChatRole.driver],
  'farmer' => const [ChatRole.buyer, ChatRole.driver],
  'driver' => const [ChatRole.farmer, ChatRole.buyer],
  _ => const [ChatRole.farmer, ChatRole.buyer, ChatRole.driver],
};

class _ChatThreadsScreenState extends ConsumerState<ChatThreadsScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  String _query = '';
  _ThreadFilter _selectedFilter = const _ThreadFilter.all();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-fetch the thread list whenever the app is foregrounded so that
    // messages sent while the WebSocket was backgrounded (and possibly
    // disconnected) are never silently missed.
    if (state == AppLifecycleState.resumed) {
      if (widget.profile.activeRole != null) {
        ref.invalidate(chatThreadsProvider(widget.profile.activeRole!));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeRole = widget.profile.activeRole;
    final threadsAsync = activeRole == null
        ? const AsyncValue.data(<ChatThread>[])
        : ref.watch(chatThreadsProvider(activeRole));
    final filters = <_ThreadFilter>[
      const _ThreadFilter.all(),
      const _ThreadFilter.unread(),
      for (final role in _peerRolesFor(widget.profile.activeRole))
        _ThreadFilter.role(role),
    ];

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
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = filters[index];
                final selected = filter == _selectedFilter;
                return ChoiceChip(
                  label: Text(filter.label()),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  labelStyle: TextStyle(
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  shape: const StadiumBorder(),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
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
                        onPressed: widget.profile.activeRole == null
                            ? null
                            : () => ref.invalidate(
                                chatThreadsProvider(widget.profile.activeRole!),
                              ),
                        child: Text('retry'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
              data: (threads) {
                final byFilter = threads
                    .where((t) => _selectedFilter.matches(t))
                    .toList();
                final filtered = _query.isEmpty
                    ? byFilter
                    : byFilter
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

class _ThreadTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: thread.conversationId,
                otherName: thread.otherName,
                otherAvatarUrl: thread.otherAvatarUrl,
                currentUserId: profile.id,
              ),
            ),
          );

          // The room may have marked the conversation as read while it was
          // open. Refresh the list once when returning so the snippet,
          // unread badge and ordering are immediately correct even if the
          // Realtime participant UPDATE arrives a little later.
          if (context.mounted && profile.activeRole != null) {
            final activeRole = profile.activeRole!;
            // Refresh both the thread list and the global nav badge immediately
            // after the room marks messages as read. Do not wait for the
            // participant Realtime UPDATE to arrive.
            ref.invalidate(chatThreadsProvider(activeRole));
            ref.invalidate(unreadConversationCountProvider(activeRole));
          }
        },
      ),
    );
  }
}
