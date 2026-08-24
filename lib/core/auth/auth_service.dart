import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import '../local_db/powersync.dart'; // exposes `db`
import '../../models/profile.dart';

class AuthService {
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

  Future<void> signInWithGoogle() {
    return supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : _mobileRedirect,
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  Stream<Profile?> watchOwnProfile() {
    final user = currentUser;
    if (user == null) return Stream.value(null);
    return db
        .watch('SELECT * FROM profile WHERE id = ?', parameters: [user.id])
        .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first));
  }

  Future<void> createOwnProfile(Profile profile) async {
    final map = profile.toInsertMap();
    await db.execute(
      'INSERT INTO profile (id, ${map.keys.join(', ')}) VALUES (?, ${map.keys.map((_) => '?').join(', ')})',
      [profile.id, ...map.values],
    );
  }

  Future<void> updateOwnProfile(Profile profile) async {
    final map = profile.toInsertMap();
    final setClause = map.keys.map((k) => '$k = ?').join(', ');
    await db.execute('UPDATE profile SET $setClause WHERE id = ?', [
      ...map.values,
      profile.id,
    ]);
  }

  Future<void> addRole(String role) async {
    final userId = currentUser!.id;
    await db.execute(
      'INSERT INTO profile_role (id, profile_id, role) VALUES (uuid(), ?, ?)',
      [userId, role],
    );
  }

  Stream<List<String>> watchOwnRoles() {
    final userId = currentUser!.id;
    return db
        .watch(
          'SELECT role FROM profile_role WHERE profile_id = ?',
          parameters: [userId],
        )
        .map((rows) => rows.map((r) => r['role'] as String).toList());
  }

  Future<void> setActiveRole(String role) async {
    final userId = currentUser!.id;
    await db.execute('UPDATE profile SET active_role = ? WHERE id = ?', [
      role,
      userId,
    ]);
  }
}
