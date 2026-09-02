import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/navigation/presentation/app_nav_shell.dart';

/// (icon, label) pairs per role, kept in lockstep with the tab lists in
/// `role_nav_shell_registry.dart`. Duplicated rather than imported from
/// there because that file builds live `NavTab`s (with screen builders)
/// for the shell itself; this widget only needs the icon/label pairs to
/// redraw the same-looking bar on a *pushed* screen and hand control
/// back to the shell's existing tab index on tap.
const Map<String, List<(IconData, String)>> _roleTabs = {
  'farmer': [
    (Icons.home_outlined, 'Home'),
    (Icons.grass_outlined, 'Harvest'),
    (Icons.receipt_long_outlined, 'Orders'),
    (Icons.chat_bubble_outline, 'Chat'),
  ],
  'buyer': [
    (Icons.home_outlined, 'Home'),
    (Icons.shopping_cart_outlined, 'Cart'),
    (Icons.receipt_long_outlined, 'Orders'),
    (Icons.chat_bubble_outline, 'Chat'),
  ],
  'driver': [
    (Icons.home_outlined, 'Home'),
    (Icons.calendar_today_outlined, 'Calendar'),
    (Icons.local_shipping_outlined, 'Deliveries'),
    (Icons.chat_bubble_outline, 'Chat'),
  ],
};

/// Drop this in as a pushed screen's `bottomNavigationBar` to keep the
/// app's standard footer visible outside the main [AppNavShell] tabs
/// (e.g. a "View all" / detail screen reached via `Navigator.push`).
/// Tapping a destination pops back to the shell and switches it to that
/// tab, rather than trying to render the tab's screen inline here.
class RoleBottomNavBar extends ConsumerWidget {
  final String role;

  const RoleBottomNavBar({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = _roleTabs[role] ?? _roleTabs['driver']!;
    // Reflects whichever tab the shell was on when this screen was
    // pushed — there's no tab that "is" this screen, so we don't try to
    // invent a selected index for it.
    final selected = ref.watch(navShellIndexProvider).clamp(0, tabs.length - 1);

    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (i) {
        ref.read(navShellIndexProvider.notifier).select(i);
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      destinations: [
        for (final (icon, label) in tabs)
          NavigationDestination(icon: Icon(icon), label: label),
      ],
    );
  }
}
