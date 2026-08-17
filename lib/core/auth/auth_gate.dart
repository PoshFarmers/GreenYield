import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import '../roles/role_profile_registry.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../../features/home/presentation/home_screen.dart';

/// Root of the app's navigation. Routes through, in order:
///   no session                -> LoginScreen
///   session, no profile row   -> CompleteProfileScreen
///   profile exists, no roles  -> RoleSelectionScreen
///   role exists, no role-specific profile row yet
///                              -> that role's completeProfileBuilder
///                                 (from roleScreensRegistry)
///   everything exists         -> HomeScreen
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
      data: (_) {
        final authService = ref.watch(authServiceProvider);
        if (!authService.isSignedIn) {
          return const LoginScreen();
        }

        final profileAsync = ref.watch(ownProfileProvider);
        return profileAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (profile) {
            if (profile == null) {
              return CompleteProfileScreen(
                onComplete: () => ref.invalidate(ownProfileProvider),
              );
            }

            final rolesAsync = ref.watch(ownRolesProvider);
            return rolesAsync.when(
              loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  Scaffold(body: Center(child: Text('$error'))),
              data: (roles) {
                if (roles.isEmpty) {
                  return const RoleSelectionScreen();
                }

                final activeRole = profile.activeRole ?? roles.first;
                final roleScreens = roleScreensRegistry[activeRole];

                if (roleScreens == null) {
                  // That role's ticket hasn't merged its registry
                  // entry yet — expected during parallel development
                  return Scaffold(
                    body: Center(
                      child: Text('$activeRole profile screens coming soon'),
                    ),
                  );
                }

                return FutureBuilder<bool>(
                  future: roleScreens.hasCompletedProfile(profile.id),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!snapshot.data!) {
                      return roleScreens.completeProfileBuilder(context);
                    }
                    return HomeScreen(profile: profile);
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
