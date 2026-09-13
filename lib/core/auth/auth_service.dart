import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/client.dart';
import '../local_db/powersync.dart'; // exposes `db`
import '../local_db/repository.dart';
import '../../models/profile.dart';

class AuthService {
  static const _mobileRedirect = 'io.supabase.greenyield://login-callback';

  // Repository.insert always supplies the local id separately, so
  // Profile.toInsertMap()'s own 'id' entry has to be stripped here —
  // the previous hand-written SQL passed profile.id AND
  // toInsertMap()['id'] into the same INSERT, producing a duplicate
  // 'id' column. This fixes that as a side effect of the refactor.
  final _profiles = Repository<Profile>(
    table: 'profile',
    fromMap: Profile.fromMap,
    toInsertMap: (p) => p.toInsertMap()..remove('id'),
  );

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
    return _profiles.watchOne(user.id);
  }

  Future<void> createOwnProfile(Profile profile) =>
      _profiles.insert(profile.id, profile);

  Future<void> updateOwnProfile(Profile profile) =>
      _profiles.update(profile.id, profile);

  /// profile_role rows have no real model to speak of (just a role
  /// string) and use a PowerSync-generated id, same as before — left
  /// as a direct db call rather than forcing it through `Repository<T>`.
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

  Future<void> updateProfileLocation({
    required GeoPoint locationPoint,
    required String locationText,
  }) async {
    final userId = currentUser!.id;

    final latitude = locationPoint.latitude;
    final longitude = locationPoint.longitude;

    final locationWkt = 'POINT($longitude $latitude)';
    final geoJson = '{"type":"Point","coordinates":[$longitude,$latitude]}';

    await db.execute(
      'UPDATE profile SET location_point = ?, location_geojson = ?, location_text = ? WHERE id = ?',
      [locationWkt, geoJson, locationText, userId],
    );
  }
}
