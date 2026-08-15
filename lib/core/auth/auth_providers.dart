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

/// The signed-in user's `profile` row, or null
final ownProfileProvider = FutureProvider<Profile?>((ref) {
  return ref.watch(authServiceProvider).fetchOwnProfile();
});