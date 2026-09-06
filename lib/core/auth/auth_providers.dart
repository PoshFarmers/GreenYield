import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import '../local_db/powersync.dart';
import '../../models/profile.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Emits on every Supabase auth state change (sign in, sign out,
/// token refresh). AuthGate watches this to decide what to show.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The signed-in user's generic profile row, or null if one hasn't
/// been created yet. Backed by a PowerSync watch stream.
final ownProfileProvider = StreamProvider<Profile?>((ref) async* {
  ref.watch(authStateChangesProvider);
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) {
    yield null;
    return;
  }
  await db.waitForFirstSync();
  yield* authService.watchOwnProfile();
});

/// Every role ('farmer'/'buyer'/'driver') the current user holds.
final ownRolesProvider = StreamProvider<List<String>>((ref) {
  ref.watch(authStateChangesProvider);
  final authService = ref.watch(authServiceProvider);
  if (!authService.isSignedIn) return Stream.value([]);
  return authService.watchOwnRoles();
});
