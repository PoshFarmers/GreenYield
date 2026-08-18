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

/// The screens/checks a role must supply so AuthGate can route to it
/// without knowing anything role-specific itself.
class RoleScreens {
  final Future<bool> Function(String profileId) hasCompletedProfile;
  final WidgetBuilder completeProfileBuilder;
  final WidgetBuilder viewBuilder;
  final WidgetBuilder editBuilder;

  const RoleScreens({
    required this.hasCompletedProfile,
    required this.completeProfileBuilder,
    required this.viewBuilder,
    required this.editBuilder,
  });
}

/// One entry per role ('farmer' | 'buyer' | 'driver'), registered by
/// that role's own feature module
final Map<String, RoleScreens> roleScreensRegistry = {
  'buyer': RoleScreens(
    hasCompletedProfile: (profileId) =>
        BuyerProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const BuyerCompleteProfileScreen(),
    viewBuilder: (context) => const BuyerProfileViewScreen(),
    editBuilder: (context) => const BuyerProfileViewScreen(),
  ),
  'farmer': RoleScreens(
    hasCompletedProfile: (profileId) =>
        FarmerProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const FarmerCompleteProfileScreen(),
    viewBuilder: (context) => const FarmerProfileViewScreen(),
    editBuilder: (context) => const FarmerProfileViewScreen(),
  ),
  'driver': RoleScreens(
    hasCompletedProfile: (profileId) =>
        DriverProfileService().hasProfile(profileId),
    completeProfileBuilder: (context) => const DriverCompleteProfileScreen(),
    viewBuilder: (context) => const DriverProfileViewScreen(),
    editBuilder: (context) => const DriverProfileViewScreen(),
  ),
};
