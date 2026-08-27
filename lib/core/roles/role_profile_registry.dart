import 'package:flutter/widgets.dart';

import '../../features/profile/buyer/buyer_profile_service.dart';
import '../../features/profile/buyer/presentation/buyer_complete_profile_screen.dart';
import '../../features/profile/buyer/presentation/buyer_profile_view_screen.dart';
import '../../features/profile/farmer/farmer_profile_service.dart';
import '../../features/profile/farmer/presentation/farmer_complete_profile_screen.dart';
import '../../features/profile/farmer/presentation/farmer_profile_view_screen.dart';
import '../../features/profile/driver/driver_profile_service.dart';
import '../../features/profile/driver/presentation/driver_complete_profile_screen.dart';
import '../../features/profile/driver/presentation/driver_profile_view_screen.dart';
import '../../models/profile.dart';

/// The screens/checks a role must supply so AuthGate can route to it
/// without knowing anything role-specific itself.
class RoleScreens {
  final Future<bool> Function(String profileId) hasCompletedProfile;
  final WidgetBuilder completeProfileBuilder;
  final Widget Function(BuildContext, Profile) viewBuilder;

  const RoleScreens({
    required this.hasCompletedProfile,
    required this.completeProfileBuilder,
    required this.viewBuilder,
  });
}

/// One entry per role ('farmer' | 'buyer' | 'driver'), registered by
/// that role's own feature module.
///
/// There is no `editBuilder` here — each role's view screen owns
/// navigation to its own edit screen directly (with the profile data
/// it already has in hand), so nothing outside that view screen needs
/// a generic way to reach the edit screen.
final Map<String, RoleScreens> roleScreensRegistry = {
  'buyer': RoleScreens(
    hasCompletedProfile: (profileId) =>
        BuyerProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const BuyerCompleteProfileScreen(),
    viewBuilder: (context, profile) =>
        BuyerProfileViewScreen(initialProfile: profile),
  ),
  'farmer': RoleScreens(
    hasCompletedProfile: (profileId) =>
        FarmerProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const FarmerCompleteProfileScreen(),
    viewBuilder: (context, profile) =>
        FarmerProfileViewScreen(initialProfile: profile),
  ),
  'driver': RoleScreens(
    hasCompletedProfile: (profileId) =>
        DriverProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const DriverCompleteProfileScreen(),
    viewBuilder: (context, profile) =>
        DriverProfileViewScreen(initialProfile: profile),
  ),
};
