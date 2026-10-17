import '../../core/supabase/client.dart';
import '../../models/farmer_public_profile.dart';

/// Read side of a farmer's public profile (name, location, crops with
/// current stock, rating, reviews) — everything a buyer sees when they
/// tap through from a listing. Server-queried via RPC rather than the
/// PowerSync mirror, for the same reason as [MarketplaceService]:
/// `profile`/`farmer_crop` only sync the signed-in user's own rows.
class FarmerPublicProfileService {
  const FarmerPublicProfileService();

  /// Null if [farmerProfileId] doesn't have a farmer_profile row.
  Future<FarmerPublicProfile?> fetchProfile(String farmerProfileId) async {
    final data = await supabase.rpc(
      'get_farmer_public_profile',
      params: {'p_farmer_id': farmerProfileId},
    );
    if (data == null) return null;
    return FarmerPublicProfile.fromMap(data as Map<String, dynamic>);
  }

  /// Every listing batch this farmer has published for [cropId] — active
  /// and past ones alike — for the "how much left out of how much was
  /// added" breakdown shown when a buyer taps a crop tile.
  Future<List<FarmerCropListing>> fetchCropListings({
    required String farmerProfileId,
    required String cropId,
  }) async {
    final data = await supabase.rpc(
      'get_farmer_crop_listings',
      params: {'p_farmer_id': farmerProfileId, 'p_crop_id': cropId},
    );
    return ((data as List?) ?? const [])
        .map((e) => FarmerCropListing.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
