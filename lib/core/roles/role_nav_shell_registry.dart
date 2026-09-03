import 'package:flutter/material.dart';

import '../../features/calendar/presentation/driver_calendar_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/cart/presentation/widgets/cart_nav_badge_icon.dart';
import '../../features/chat/presentation/chat_threads_screen.dart';
import '../../features/chat/presentation/widgets/chat_nav_badge_icon.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/farmer_home_screen.dart';
import '../../features/listings/presentation/my_listings_screen.dart';
import '../../features/marketplace/presentation/marketplace_screen.dart';
import '../../features/navigation/presentation/app_nav_shell.dart';
import '../../features/orders/presentation/buyer_orders_screen.dart';
import '../../features/orders/presentation/driver_deliveries_screen.dart';
import '../../features/orders/presentation/farmer_orders_screen.dart';
import '../../models/profile.dart';

/// Builds the correct bottom-nav shell for [profile]'s active role.
/// Each role gets its own tab set (per the Figma):
///   Farmer -> Home, Harvest,  Orders, Chat
///   Buyer  -> Home, Cart,     Orders, Chat
///   Driver -> Home, Calendar, Deliveries, Chat
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
  final farmerHomeTab = NavTab(
    label: 'Home',
    icon: Icons.home_outlined,
    builder: (_) => FarmerHomeScreen(profile: profile),
  );
  final chatTab = NavTab(
    label: 'Chat',
    icon: Icons.chat_bubble_outline,
    iconBuilder: (_) => ChatNavBadgeIcon(activeRole: activeRole),
    builder: (_) => ChatThreadsScreen(profile: profile),
  );

  switch (activeRole) {
    case 'farmer':
      return AppNavShell(
        tabs: [
          farmerHomeTab,
          NavTab(
            label: 'Harvest',
            icon: Icons.grass_outlined,
            builder: (_) => MyListingsScreen(profile: profile),
          ),
          NavTab(
            label: 'Orders',
            icon: Icons.receipt_long_outlined,
            builder: (_) => FarmerOrdersScreen(profile: profile),
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
            iconBuilder: (_) => CartNavBadgeIcon(buyerProfileId: profile.id),
            builder: (_) => CartScreen(profile: profile),
          ),
          NavTab(
            label: 'Orders',
            icon: Icons.receipt_long_outlined,
            builder: (_) => BuyerOrdersScreen(profile: profile),
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
            builder: (_) => DriverDeliveriesScreen(profile: profile),
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
