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
      SELECT crop.id, crop.name, crop.category, crop.fallback_image_url,
             farmer_crop.description, farmer_crop.default_price_per_kg,
             farmer_crop.image_url
      FROM farmer_crop
      JOIN crop ON crop.id = farmer_crop.crop_id
      WHERE farmer_crop.farmer_profile_id = ?
      ''',
          parameters: [profileId],
        )
        .map((rows) {
          final crops = rows.map(FarmerCrop.fromMap).toList();
          return FarmerProfile(profileId: profileId, crops: crops);
        });
  }

  /// Creates the farmer_profile row and, if any [crops] are given, their
  /// farmer_crop rows. [crops] may be empty — this is what lets the
  /// onboarding step be skipped: a bare farmer_profile row alone is
  /// enough for `hasProfile` to pass.
  Future<void> createProfile(
    String profileId,
    List<FarmerCropInput> crops,
  ) async {
    await db.execute(
      'INSERT INTO farmer_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    await _addCrops(profileId, crops);
  }

  /// Inserts or updates a single crop on the farmer's menu, leaving the
  /// rest untouched — used by the Crops Grown section of the profile,
  /// where crops are edited one at a time rather than as a whole set.
  Future<void> upsertCrop(String profileId, FarmerCropInput crop) async {
    final id = configFor('farmer_crop').compositeKey!
        .buildId([profileId, crop.cropId]);

    final existing = await db.getOptional(
      'SELECT id FROM farmer_crop WHERE id = ?',
      [id],
    );

    if (existing == null) {
      await _addCrops(profileId, [crop]);
      return;
    }

    await db.execute(
      '''
      UPDATE farmer_crop
      SET description = ?, default_price_per_kg = ?, image_url = ?
      WHERE id = ?
      ''',
      [crop.description, crop.defaultPricePerKg, crop.imageUrl, id],
    );
  }

  Future<void> removeCrop(String profileId, String cropId) async {
    final id = configFor('farmer_crop').compositeKey!
        .buildId([profileId, cropId]);
    await db.execute('DELETE FROM farmer_crop WHERE id = ?', [id]);
  }

  /// Builds each row's composite id via the registry's CompositeKey
  /// instead of hand-interpolating "$profileId:$cropId" — same idea
  /// the connector now uses on the way back out to Supabase.
  Future<void> _addCrops(String profileId, List<FarmerCropInput> crops) async {
    final compositeKey = configFor('farmer_crop').compositeKey!;
    for (final crop in crops) {
      final id = compositeKey.buildId([profileId, crop.cropId]);
      await db.execute(
        '''
        INSERT INTO farmer_crop
          (id, farmer_profile_id, crop_id, description, default_price_per_kg, image_url)
        VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          profileId,
          crop.cropId,
          crop.description,
          crop.defaultPricePerKg,
          crop.imageUrl,
        ],
      );
    }
  }
}
