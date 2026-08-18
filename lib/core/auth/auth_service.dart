import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import '../../models/profile.dart';

/// Every bit of auth logic goes through this class — screens should
/// never call `supabase.auth.*` directly
class AuthService {
  /// Custom scheme registered in AndroidManifest.xml / Info.plist so
  /// the OAuth browser flow can redirect back into the app on mobile.
  /// Not needed on web — the browser flow redirects in-page there.
  static const _mobileRedirect = 'io.supabase.greenyield://login-callback';

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  User? get currentUser => supabase.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return supabase.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Opens the system browser for Google's OAuth consent screen and
  /// redirects back into the app on success. Auth state changes are
  /// picked up via [authStateChanges] — this method doesn't return a
  /// session directly.
  Future<void> signInWithGoogle() {
    return supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : _mobileRedirect,
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// Returns the current user's generic profile row, or null if one
  /// hasn't been created yet.
  Future<Profile?> fetchOwnProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await supabase
        .from('profile_read')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return Profile.fromMap(row);
  }

  /// Creates the generic profile row for the signed-in user.
  Future<void> createOwnProfile(Profile profile) async {
    await supabase.from('profile').insert(profile.toInsertMap());
  }

  // Updates own profile
  Future<void> updateOwnProfile(Profile profile) async {
    await supabase
        .from('profile')
        .update(profile.toInsertMap())
        .eq('id', profile.id);
  }

  /// Grants a role to the current user (inserts into profile_role).
  Future<void> addRole(String role) async {
    final userId = currentUser!.id;
    await supabase.from('profile_role').insert({
      'profile_id': userId,
      'role': role,
    });
  }

  /// Returns every role the current user currently holds.
  Future<List<String>> fetchOwnRoles() async {
    final userId = currentUser!.id;
    final rows = await supabase
        .from('profile_role')
        .select('role')
        .eq('profile_id', userId);
    return rows.map((row) => row['role'] as String).toList();
  }

  /// Which role's UI is currently shown.
  Future<void> setActiveRole(String role) async {
    final userId = currentUser!.id;
    await supabase
        .from('profile')
        .update({'active_role': role})
        .eq('id', userId);
  }
}
