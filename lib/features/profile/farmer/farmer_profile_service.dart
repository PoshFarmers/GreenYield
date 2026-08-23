import '../../../core/local_db/powersync.dart';
import '../../../models/farmer_profile.dart';

class FarmerProfileService {
  Stream<List<Crop>> watchAllCrops() {
    return db
        .watch('SELECT * FROM crop ORDER BY name')
        .map((rows) => rows.map((r) => Crop.fromMap(r)).toList());
  }

  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT profile_id FROM farmer_profile WHERE profile_id = ?',
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
          final crops = rows.map((r) => Crop.fromMap(r)).toList();
          return FarmerProfile(profileId: profileId, crops: crops);
        });
  }

  Future<void> createProfile(String profileId, List<String> cropIds) async {
    await db.execute(
      'INSERT INTO farmer_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    for (final cropId in cropIds) {
      await db.execute(
        'INSERT INTO farmer_crop (id, farmer_profile_id, crop_id) VALUES (?, ?, ?)',
        ['$profileId:$cropId', profileId, cropId],
      );
    }
  }

  Future<void> updateCrops(String profileId, List<String> cropIds) async {
    await db.execute('DELETE FROM farmer_crop WHERE farmer_profile_id = ?', [
      profileId,
    ]);
    for (final cropId in cropIds) {
      await db.execute(
        'INSERT INTO farmer_crop (id, farmer_profile_id, crop_id) VALUES (?, ?, ?)',
        ['$profileId:$cropId', profileId, cropId],
      );
    }
  }
}
