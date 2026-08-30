import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/notification_providers.dart';
import '../notification_screen.dart';

/// Bell icon + live unread badge for app bars. Drop it into any role's
/// `AppBar.actions` — it's fully self-contained (provider-driven count,
/// navigation to [NotificationScreen]).
class NotificationBadgeWidget extends ConsumerWidget {
  const NotificationBadgeWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final count = unreadAsync.asData?.value ?? 0;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationScreen())),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: AppColors.warnAmber,
        textColor: AppColors.deepForestGreen,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
