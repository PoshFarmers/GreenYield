import '../../../core/local_db/powersync.dart';
import '../../../models/buyer_profile.dart';

class BuyerProfileService {
  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT profile_id FROM buyer_profile WHERE profile_id = ?',
      [profileId],
    );
    return row != null;
  }

  Stream<BuyerProfile?> watchOwnProfile(String profileId) {
    return db
        .watch(
          'SELECT * FROM buyer_profile WHERE profile_id = ?',
          parameters: [profileId],
        )
        .map((rows) => rows.isEmpty ? null : BuyerProfile.fromMap(rows.first));
  }

  Future<void> createProfile(BuyerProfile profile) async {
    final map = profile.toInsertMap();
    await db.execute(
      'INSERT INTO buyer_profile (id, ${map.keys.join(', ')}) VALUES (?, ${map.keys.map((_) => '?').join(', ')})',
      [profile.profileId, ...map.values],
    );
  }

  Future<void> updateProfile(BuyerProfile profile) async {
    await db.execute(
      'UPDATE buyer_profile SET buyer_type = ?, buyer_label = ? WHERE profile_id = ?',
      [profile.buyerType, profile.buyerLabel, profile.profileId],
    );
  }
}
