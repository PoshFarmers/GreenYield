import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import '../roles/role_profile_registry.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/location_setup_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../roles/role_nav_shell_registry.dart';

/// Root of the app's navigation. Routes through, in order:
///   no session                -> LoginScreen
///   session, no profile row   -> CompleteProfileScreen
///   profile exists, no roles  -> RoleSelectionScreen
///   roles exist, no location  -> LocationSetupScreen
///   location exists, role exists, no role-specific profile row yet
///                              -> that role's completeProfileBuilder
///                                 (from roleScreensRegistry)
///   everything exists         -> HomeScreen
///
/// Every `when` uses `skipLoadingOnReload` so a provider rebuild (token
/// refresh, app resume, invalidate) keeps the current screen up instead of
/// replacing the whole nav shell with a spinner. However, cached values
/// from a previous authentication state or user are treated as loading.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  // Cache for the role-profile completeness check. The same Future is reused
  // across rebuilds while it's pending or has resolved `true`. While the
  // result is `false` it's re-run on each rebuild, because the onboarding
  // screens call `ref.invalidate(ownProfileProvider)` precisely to get that
  // re-check after they finish.
  String? _completionKey;
  bool? _completionResult;
  Future<bool>? _completionFuture;
  int _completionToken = 0;

  Future<bool> _completionFor(
    String profileId,
    String role,
    RoleScreens screens,
  ) {
    final key = '$profileId:$role';
    if (_completionFuture == null ||
        _completionKey != key ||
        _completionResult == false) {
      final token = ++_completionToken;
      _completionKey = key;
      _completionResult = null;
      _completionFuture = screens.hasCompletedProfile(profileId).then((value) {
        if (token == _completionToken) _completionResult = value;
        return value;
      });
    }
    return _completionFuture!;
  }

  void _resetCompletion() {
    _completionToken++;
    _completionKey = null;
    _completionResult = null;
    _completionFuture = null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      skipLoadingOnReload: true,
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
      data: (_) {
        final authService = ref.watch(authServiceProvider);

        if (!authService.isSignedIn) {
          _resetCompletion();
          return const LoginScreen();
        }

        const spinner = Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );

        final authUserId = ref.watch(authUserIdProvider);
        final profileAsync = ref.watch(ownProfileProvider);

        // A reload can retain the previous value, such as null while logged
        // out or another user's profile. Don't trust it until the current
        // user's profile has arrived.
        final cachedProfile = profileAsync.asData?.value;
        if (profileAsync.isLoading &&
            (cachedProfile == null || cachedProfile.id != authUserId)) {
          return spinner;
        }

        return profileAsync.when(
          skipLoadingOnReload: true,
          loading: () => spinner,
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (profile) {
            if (profile == null) {
              return CompleteProfileScreen(
                onComplete: () => ref.invalidate(ownProfileProvider),
              );
            }

            final rolesAsync = ref.watch(ownRolesProvider);

            // The same stale-value issue applies to roles: an empty list
            // retained from the logged-out state must not trigger role
            // selection while the current user's roles are still loading.
            if (rolesAsync.isLoading &&
                (rolesAsync.asData?.value ?? const <String>[]).isEmpty) {
              return spinner;
            }

            return rolesAsync.when(
              skipLoadingOnReload: true,
              loading: () => spinner,
              error: (error, _) =>
                  Scaffold(body: Center(child: Text('$error'))),
              data: (roles) {
                if (roles.isEmpty) {
                  return const RoleSelectionScreen();
                }

                final activeRole = profile.activeRole ?? roles.first;

                // Location lives on the common profile row, not a role
                // table, so check it before any role-specific screens.
                if (profile.locationText == null ||
                    profile.locationPoint == null) {
                  return LocationSetupScreen(profile: profile);
                }

                final roleScreens = roleScreensRegistry[activeRole];

                if (roleScreens == null) {
                  // That role's ticket hasn't merged its registry entry yet.
                  return Scaffold(
                    body: Center(
                      child: Text('$activeRole profile screens coming soon'),
                    ),
                  );
                }

                return FutureBuilder<bool>(
                  future: _completionFor(profile.id, activeRole, roleScreens),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return spinner;
                    }

                    if (!snapshot.data!) {
                      return roleScreens.completeProfileBuilder(context);
                    }

                    return buildNavShellForRole(profile, activeRole);
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
