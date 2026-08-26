import '../../../core/local_db/powersync.dart'; // exposes `db`
import '../../../core/local_db/repository.dart';
import '../../../core/local_db/table_registry.dart';
import '../../../models/farmer_profile.dart';

class FarmerProfileService {
  // crop is a read-only reference table for the client (RLS only grants
  // select) — Repository is still useful here purely for watchAll, so
  // toInsertMap is never actually invoked.
  final _crops = Repository<Crop>(
    table: 'crop',
    fromMap: Crop.fromMap,
    toInsertMap: (_) =>
        throw UnsupportedError('crop is read-only from the client'),
  );

  Stream<List<Crop>> watchAllCrops() => _crops.watchAll(orderBy: 'name');

  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT id FROM farmer_profile WHERE profile_id = ?',
      [profileId],
    );
    return row != null;
  }

  Stream<FarmerProfile?> watchOwnProfile(String profileId) {
    return db
        .watch(
          '''
      SELECT crop.id, crop.name, crop.category
      FROM farmer_crop
      JOIN crop ON crop.id = farmer_crop.crop_id
      WHERE farmer_crop.farmer_profile_id = ?
      ''',
          parameters: [profileId],
        )
        .map((rows) {
          final crops = rows.map(Crop.fromMap).toList();
          return FarmerProfile(profileId: profileId, crops: crops);
        });
  }

  Future<void> createProfile(String profileId, List<String> cropIds) async {
    await db.execute(
      'INSERT INTO farmer_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    await _addCrops(profileId, cropIds);
  }

  Future<void> updateCrops(String profileId, List<String> cropIds) async {
    await db.execute('DELETE FROM farmer_crop WHERE farmer_profile_id = ?', [
      profileId,
    ]);
    await _addCrops(profileId, cropIds);
  }

  /// Builds each row's composite id via the registry's CompositeKey
  /// instead of hand-interpolating "$profileId:$cropId" — same idea
  /// the connector now uses on the way back out to Supabase.
  Future<void> _addCrops(String profileId, List<String> cropIds) async {
    final compositeKey = configFor('farmer_crop').compositeKey!;
    for (final cropId in cropIds) {
      final id = compositeKey.buildId([profileId, cropId]);
      await db.execute(
        'INSERT INTO farmer_crop (id, farmer_profile_id, crop_id) VALUES (?, ?, ?)',
        [id, profileId, cropId],
      );
    }
  }
}
