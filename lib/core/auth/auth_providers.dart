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
/// been created yet. Backed by a PowerSync watch stream, so it now
/// updates live whenever the local `profile` row changes — no manual
/// invalidation needed after a write, on this device or synced in
/// from another.
final ownProfileProvider = StreamProvider<Profile?>((ref) {
  ref.watch(authStateChangesProvider); // rebuild whenever auth state changes
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) return Stream.value(null);
  return authService.watchOwnProfile();
});

/// Every role ('farmer'/'buyer'/'driver') the current user currently
/// holds. Also stream-backed — updates automatically once addRole()
/// writes to profile_role, without needing an explicit invalidate.
final ownRolesProvider = StreamProvider<List<String>>((ref) {
  ref.watch(authStateChangesProvider);
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) return Stream.value([]);
  return authService.watchOwnRoles();
});
