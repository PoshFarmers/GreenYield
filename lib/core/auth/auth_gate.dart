import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';

/// Root of the app's navigation. Watches auth + profile state
/// and decides what to show:
///   no session               -> LoginScreen
///   session, no profile row  -> CompleteProfileScreen
///   session, profile exists  -> HomeScreen
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
      data: (_) {
        final authService = ref.watch(authServiceProvider);
        if (!authService.isSignedIn) {
          return const LoginScreen();
        }

        final profileAsync = ref.watch(ownProfileProvider);
        return profileAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (profile) {
            if (profile == null) {
              return CompleteProfileScreen(
                onComplete: () => ref.invalidate(ownProfileProvider),
              );
            }
            return HomeScreen(profile: profile);
          },
        );
      },
    );
  }
}