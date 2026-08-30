import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../models/notification_item.dart';

/// One notification row: type icon, title, description, relative
/// timestamp, and an unread indicator (accent bar + dot). Wrap in a
/// `Dismissible` where swipe-to-dismiss is needed (see NotificationScreen).
class NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  const NotificationCard({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final (icon, iconColor) = _iconFor(notification);

    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                width: 4,
                color: unread ? _accentFor(notification) : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: iconColor.withValues(alpha: 0.15),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.deepForestGreen,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(notification.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedGray,
                          ),
                        ),
                      ],
                    ),
                    if (notification.body != null &&
                        notification.body!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.freshLeafGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _accentFor(NotificationItem n) {
    if (n.type == 'payment_failed') return Colors.redAccent;
    return AppColors.freshLeafGreen;
  }

  (IconData, Color) _iconFor(NotificationItem n) {
    switch (n.category) {
      case NotificationCategory.orders:
        return (Icons.receipt_long_outlined, AppColors.freshLeafGreen);
      case NotificationCategory.payments:
        return (Icons.payments_outlined, AppColors.warnAmber);
      case NotificationCategory.logistics:
        return (Icons.local_shipping_outlined, AppColors.deepForestGreen);
      case NotificationCategory.messages:
        return (Icons.chat_bubble_outline, AppColors.freshLeafGreen);
      case NotificationCategory.account:
        return (Icons.person_outline, AppColors.deepForestGreen);
      case NotificationCategory.system:
        return (Icons.info_outline, AppColors.mutedGray);
    }
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }
}
