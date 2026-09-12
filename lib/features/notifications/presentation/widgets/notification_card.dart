import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../models/notification_item.dart';

/// One notification row: type icon, title, description, relative
/// timestamp, and an unread indicator (accent bar + dot). Tap to expand
/// and show the full message body. Wrap in a `Dismissible` where
/// swipe-to-dismiss is needed (see NotificationScreen).
class NotificationCard extends StatefulWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  const NotificationCard({super.key, required this.notification, this.onTap});

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
    // Call the onTap callback if provided
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final unread = !widget.notification.isRead;
    final (icon, iconColor) = _iconFor(widget.notification);
    final hasBody =
        widget.notification.body != null &&
        widget.notification.body!.isNotEmpty;

    return Material(
      color: AppColors.cream,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: hasBody ? _toggleExpanded : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                width: 4,
                color: unread
                    ? _accentFor(widget.notification)
                    : Colors.transparent,
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
                            widget.notification.title,
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
                          _relativeTime(widget.notification.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedGray,
                          ),
                        ),
                      ],
                    ),
                    if (hasBody) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.notification.body!,
                        maxLines: _isExpanded ? null : 2,
                        overflow: _isExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      if (_isExpanded) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Tap to collapse',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.freshLeafGreen.withValues(
                                alpha: 0.7,
                              ),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
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
              ] else if (hasBody) ...[
                const SizedBox(width: 8),
                RotationTransition(
                  turns: Tween<double>(
                    begin: 0,
                    end: 0.5,
                  ).animate(_expandController),
                  child: Icon(
                    Icons.expand_more,
                    color: AppColors.mutedGray.withValues(alpha: 0.6),
                    size: 20,
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
