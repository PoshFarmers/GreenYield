import '../../../core/local_db/repository.dart';
import '../../../models/buyer_profile.dart';

class BuyerProfileService {
  // buyer_profile is a 1:1 table where local id == profile id, and
  // toInsertMap() already includes 'profile_id' itself (redundant with
  // the local id, but that mirrors the existing table shape) — see
  // BuyerProfile.toInsertMap in models/buyer_profile.dart.
  final _repo = Repository<BuyerProfile>(
    table: 'buyer_profile',
    fromMap: BuyerProfile.fromMap,
    toInsertMap: (p) => p.toInsertMap(),
  );

  Future<bool> hasProfile(String profileId) => _repo.exists(profileId);

  Stream<BuyerProfile?> watchOwnProfile(String profileId) =>
      _repo.watchOne(profileId);

  Future<void> createProfile(BuyerProfile profile) =>
      _repo.insert(profile.profileId, profile);

  Future<void> updateProfile(BuyerProfile profile) =>
      _repo.update(profile.profileId, profile);
}
