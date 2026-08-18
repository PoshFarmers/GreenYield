import '../../../core/supabase/client.dart';
import '../../../models/buyer_profile.dart';

class BuyerProfileService {
  Future<bool> hasProfile(String profileId) async {
    final row = await supabase
        .from('buyer_profile')
        .select('profile_id')
        .eq('profile_id', profileId)
        .maybeSingle();
    return row != null;
  }

  Future<BuyerProfile?> fetchOwnProfile(String profileId) async {
    final row = await supabase
        .from('buyer_profile')
        .select()
        .eq('profile_id', profileId)
        .maybeSingle();
    if (row == null) return null;
    return BuyerProfile.fromMap(row);
  }

  Future<void> createProfile(BuyerProfile profile) async {
    await supabase.from('buyer_profile').insert(profile.toInsertMap());
  }

  Future<void> updateProfile(BuyerProfile profile) async {
    await supabase
        .from('buyer_profile')
        .update({
          'buyer_type': profile.buyerType,
          'buyer_label': profile.buyerLabel,
        })
        .eq('profile_id', profile.profileId);
  }
}
