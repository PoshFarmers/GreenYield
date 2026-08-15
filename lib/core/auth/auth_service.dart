import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import '../../models/profile.dart';

/// Every bit of auth logic goes through this class — screens should
/// never call `supabase.auth.*` directly, so we have exactly one
/// place to change if the auth strategy changes later.
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
      redirectTo: kIsWeb ? null : _mobileRedirect,
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// Returns the current user's generic profile row, or null if one
  /// hasn't been created yet (e.g. straight after a fresh sign-up or
  /// a first-time Google sign-in).
  Future<Profile?> fetchOwnProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await supabase
        .from('profile')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return Profile.fromMap(row);
  }

  /// Creates the generic profile row for the signed-in user. Call
  /// this once, right after sign-up/first Google sign-in — see
  /// CompleteProfileScreen.
  Future<void> createOwnProfile(Profile profile) async {
    await supabase.from('profile').insert(profile.toInsertMap());
  }
}