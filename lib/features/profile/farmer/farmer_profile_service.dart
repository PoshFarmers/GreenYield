import '../../../core/supabase/client.dart';
import '../../../models/farmer_profile.dart';

class FarmerProfileService {
  Future<bool> hasProfile(String profileId) async {
    final row = await supabase
        .from('farmer_profile')
        .select('profile_id')
        .eq('profile_id', profileId)
        .maybeSingle();
    return row != null;
  }

  Future<List<Crop>> fetchAllCrops() async {
    final rows = await supabase.from('crop').select().order('name');
    return (rows as List)
        .map((row) => Crop.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<FarmerProfile?> fetchOwnProfile(String profileId) async {
    final profileRow = await supabase
        .from('farmer_profile')
        .select('profile_id')
        .eq('profile_id', profileId)
        .maybeSingle();
    if (profileRow == null) return null;

    final cropRows = await supabase
        .from('farmer_crop')
        .select('crop(id, name, category)')
        .eq('farmer_profile_id', profileId);

    final crops = (cropRows as List)
        .map((row) => Crop.fromMap(row['crop'] as Map<String, dynamic>))
        .toList();

    return FarmerProfile(profileId: profileId, crops: crops);
  }

  Future<void> createProfile(String profileId, List<String> cropIds) async {
    await supabase.from('farmer_profile').insert({'profile_id': profileId});
    if (cropIds.isNotEmpty) {
      await supabase
          .from('farmer_crop')
          .insert(
            cropIds
                .map(
                  (cropId) => {
                    'farmer_profile_id': profileId,
                    'crop_id': cropId,
                  },
                )
                .toList(),
          );
    }
  }

  // Replaces the farmer's crop selection wholesale rather than diffing
  // add/remove sets — simpler, and cheap enough for this table's size.
  Future<void> updateCrops(String profileId, List<String> cropIds) async {
    await supabase
        .from('farmer_crop')
        .delete()
        .eq('farmer_profile_id', profileId);
    if (cropIds.isNotEmpty) {
      await supabase
          .from('farmer_crop')
          .insert(
            cropIds
                .map(
                  (cropId) => {
                    'farmer_profile_id': profileId,
                    'crop_id': cropId,
                  },
                )
                .toList(),
          );
    }
  }
}
