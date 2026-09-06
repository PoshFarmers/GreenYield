import 'package:flutter/material.dart';

import '../../features/calendar/presentation/driver_calendar_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/listings/presentation/my_listings_screen.dart';
import '../../features/marketplace/presentation/marketplace_screen.dart';
import '../../features/navigation/presentation/app_nav_shell.dart';
import '../../models/profile.dart';
import '../widgets/coming_soon_screen.dart';

/// Builds the correct bottom-nav shell for [profile]'s active role.
/// Each role gets its own tab set (per the Figma):
///   Farmer -> Home, Harvest,  Orders, Chat
///   Buyer  -> Home, Cart,     Orders, Chat
///   Driver -> Home, Calendar, Deliveries, Chat
///
/// Only Home is wired to a real screen right now. The rest — including
/// Chat, until the messaging branch merges — are `ComingSoonScreen`
/// placeholders. Swap those out in place; the shell itself never needs
/// to change.
Widget buildNavShellForRole(Profile rawProfile, String activeRole) {
  // AuthGate falls back to `roles.first` when profile.active_role is
  // null, but that fallback lived only in its local variable — anything
  // downstream reading profile.activeRole (e.g. AppHeader resolving the
  // profile screen) would still see null and silently render nothing.
  // Stamping it on here keeps the whole subtree consistent.
  final profile = rawProfile.activeRole == null
      ? rawProfile.copyWith(activeRole: activeRole)
      : rawProfile;

  final homeTab = NavTab(
    label: 'Home',
    icon: Icons.home_outlined,
    builder: (_) => HomeScreen(profile: profile),
  );
  final chatTab = NavTab(
    label: 'Chat',
    icon: Icons.chat_bubble_outline,
    builder: (_) => const ComingSoonScreen(title: 'Chat'),
  );

  switch (activeRole) {
    case 'farmer':
      return AppNavShell(
        tabs: [
          homeTab,
          NavTab(
            label: 'Harvest',
            icon: Icons.grass_outlined,
            builder: (_) => MyListingsScreen(profile: profile),
          ),
          NavTab(
            label: 'Orders',
            icon: Icons.receipt_long_outlined,
            builder: (_) => const ComingSoonScreen(title: 'Orders'),
          ),
          chatTab,
        ],
      );

    case 'buyer':
      return AppNavShell(
        tabs: [
          // The buyer's "home" is the marketplace, not the shared
          // HomeScreen the other roles still use.
          NavTab(
            label: 'Home',
            icon: Icons.home_outlined,
            builder: (_) => MarketplaceScreen(profile: profile),
          ),
          NavTab(
            label: 'Cart',
            icon: Icons.shopping_cart_outlined,
            builder: (_) => CartScreen(profile: profile),
          ),
          NavTab(
            label: 'Orders',
            icon: Icons.receipt_long_outlined,
            builder: (_) => const ComingSoonScreen(title: 'Orders'),
          ),
          chatTab,
        ],
      );

    case 'driver':
      return AppNavShell(
        tabs: [
          homeTab,
          NavTab(
            label: 'Calendar',
            icon: Icons.calendar_today_outlined,
            builder: (_) => DriverCalendarScreen(profile: profile),
          ),
          NavTab(
            label: 'Deliveries',
            icon: Icons.local_shipping_outlined,
            builder: (_) => const ComingSoonScreen(title: 'Deliveries'),
          ),
          chatTab,
        ],
      );

    default:
      // Shouldn't happen (AuthGate only calls this once a role is
      // active), but fall back to a Home-only shell rather than crash.
      return AppNavShell(tabs: [homeTab]);
  }
}
