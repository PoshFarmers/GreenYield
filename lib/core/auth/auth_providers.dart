import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import '../../models/profile.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Emits on every Supabase auth state change (sign in, sign out,
/// token refresh). AuthGate watches this to decide what to show.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The signed-in user's generic profile row, or null if one hasn't
/// been created yet. Automatically re-fetches whenever the auth
/// state changes (sign-in, sign-out, switching accounts) — Riverpod
/// handles the caching/re-fetch bookkeeping that AuthGate used to do
/// by hand with a StatefulWidget.
///
/// After CompleteProfileScreen creates the row, call
/// `ref.invalidate(ownProfileProvider)` to force a re-fetch rather
/// than tracking a manual "reload" callback.
final ownProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateChangesProvider); // rebuild whenever auth state changes
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) return null;
  return authService.fetchOwnProfile();
});

/// Every role ('farmer'/'buyer'/'driver') the current user currently
/// holds. Empty until they complete RoleSelectionScreen at least once.
/// Invalidate this after adding a role so AuthGate re-checks it.
final ownRolesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(authStateChangesProvider);
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) return [];
  return authService.fetchOwnRoles();
});
