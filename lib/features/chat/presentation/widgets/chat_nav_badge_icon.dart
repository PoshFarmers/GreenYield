import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/chat_providers.dart';

/// Drop-in icon for the Chat tab's `NavTab.iconBuilder` on every role's
/// bottom nav shell. Shows the same yellow notification-badge styling
/// as `NotificationBadgeWidget`, but sourced from
/// `unreadConversationCountProvider` — a live count of distinct
/// *threads* with unread messages, not total unread messages.
class ChatNavBadgeIcon extends ConsumerWidget {
  final IconData icon;

  const ChatNavBadgeIcon({super.key, this.icon = Icons.chat_bubble_outline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadConversationCountProvider).asData?.value ?? 0;

    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.warnAmber,
      textColor: AppColors.deepForestGreen,
      child: Icon(icon),
    );
  }
}
