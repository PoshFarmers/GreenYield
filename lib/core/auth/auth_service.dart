import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import '../../models/profile.dart';

/// Every bit of auth logic goes through this class
class AuthService {
  /// Custom scheme registered in AndroidManifest.xml / Info.plist
  static const _mobileRedirect = 'io.supabase.greenyield://login-callback';

  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  User? get currentUser => supabase.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    //return supabase.auth.signUp(email: email, password: password);
    return supabase.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: kIsWeb ? Uri.base.origin : _mobileRedirect,
    );
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Opens the system browser for Google's OAuth consent screen
  /// and redirects back into the app on success.
  Future<void> signInWithGoogle() {
    return supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : _mobileRedirect,
      queryParams: {'prompt': 'select_account'},
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// Returns the current user's generic profile row
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

  /// Creates the generic profile row for the signed-in user
  Future<void> createOwnProfile(Profile profile) async {
    await supabase.from('profile').insert(profile.toInsertMap());
  }
}