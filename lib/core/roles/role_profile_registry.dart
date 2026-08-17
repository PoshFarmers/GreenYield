import 'package:flutter/widgets.dart';

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
  // 'buyer': RoleScreens(...),
  // 'farmer': RoleScreens(...),
  // 'driver': RoleScreens(...),
};
