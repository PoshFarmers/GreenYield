import '../../../core/supabase/client.dart';
import '../../../models/driver_profile.dart';

class DriverProfileService {
  Future<bool> hasProfile(String profileId) async {
    final row = await supabase
        .from('driver_profile')
        .select('profile_id')
        .eq('profile_id', profileId)
        .maybeSingle();
    return row != null;
  }

  // A driver can register several vehicles over time (a "My Vehicles"
  // flow, outside the scope of these screens), but only the first one —
  // created alongside driver_profile at registration — is surfaced here.
  Future<DriverProfile?> fetchOwnProfile(String profileId) async {
    final profileRow = await supabase
        .from('driver_profile')
        .select('profile_id')
        .eq('profile_id', profileId)
        .maybeSingle();
    if (profileRow == null) return null;

    final vehicleRow = await supabase
        .from('vehicle')
        .select()
        .eq('driver_profile_id', profileId)
        .order('created_at')
        .limit(1)
        .maybeSingle();

    return DriverProfile(
      profileId: profileId,
      primaryVehicle: vehicleRow == null ? null : Vehicle.fromMap(vehicleRow),
    );
  }

  Future<void> createProfile(String profileId, Vehicle vehicle) async {
    await supabase.from('driver_profile').insert({'profile_id': profileId});
    await supabase.from('vehicle').insert(vehicle.toInsertMap());
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    await supabase.from('vehicle').insert(vehicle.toInsertMap());
  }

  Future<void> updateVehicle(String vehicleId, Vehicle vehicle) async {
    await supabase
        .from('vehicle')
        .update({
          'vehicle_type': vehicle.vehicleType,
          'plate_number': vehicle.plateNumber,
          'max_load_kg': vehicle.maxLoadKg,
          'preferred_min_load_kg': vehicle.preferredMinLoadKg,
        })
        .eq('id', vehicleId);
  }
}
