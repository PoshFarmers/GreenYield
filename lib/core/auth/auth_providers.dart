import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import '../../models/profile.dart';

/// Single shared instance — screens/providers should read this
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Drives AuthGate's top-level branch
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Recomputes only when the signed-in user actually changes
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.maybeWhen(
    data: (state) => state.session?.user.id,
    orElse: () => null,
  );
});

/// The signed-in user's `profile` row, or null
final ownProfileProvider = FutureProvider<Profile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(authServiceProvider).fetchOwnProfile();
});
