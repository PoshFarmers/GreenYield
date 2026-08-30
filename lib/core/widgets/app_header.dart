import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../roles/role_profile_registry.dart';
import '../../models/profile.dart';
import 'avatar_image.dart';

/// The app's common header: brand mark on the left, notification bell
/// and the signed-in user's avatar on the right. Used by the main
/// nav-shell screens — screens with their own dedicated title (edit
/// forms, onboarding steps, ...) keep using a plain `AppBar` instead.
///
/// Tapping the avatar opens that role's profile view screen, resolved
/// through [roleScreensRegistry] so this widget stays role-agnostic.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final Profile profile;

  /// Shown as an unread dot on the bell. Wire this up once the
  /// notification feature has a Dart data layer.
  final bool hasUnreadNotifications;

  /// No-op by default — the notifications screen doesn't exist yet.
  final VoidCallback? onNotificationsTap;

  const AppHeader({
    super.key,
    required this.profile,
    this.hasUnreadNotifications = false,
    this.onNotificationsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleScreens = profile.activeRole != null
        ? roleScreensRegistry[profile.activeRole]
        : null;

    return AppBar(
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'app_name'.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'notifications'.tr(),
          onPressed: onNotificationsTap,
          icon: Badge(
            isLabelVisible: hasUnreadNotifications,
            smallSize: 8,
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
        if (roleScreens != null)
          IconButton(
            tooltip: 'my_profile'.tr(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => roleScreens.viewBuilder(context, profile),
              ),
            ),
            icon: AvatarImage(path: profile.avatarUrl, radius: 16),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}
