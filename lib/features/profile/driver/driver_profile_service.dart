import '../../../core/local_db/powersync.dart';
import '../../../models/driver_profile.dart';

class DriverProfileService {
  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT profile_id FROM driver_profile WHERE profile_id = ?',
      [profileId],
    );
    return row != null;
  }

  Stream<DriverProfile?> watchOwnProfile(String profileId) {
    return db
        .watch(
          'SELECT * FROM vehicle WHERE driver_profile_id = ? ORDER BY id LIMIT 1',
          parameters: [profileId],
        )
        .map((rows) {
          return DriverProfile(
            profileId: profileId,
            primaryVehicle: rows.isEmpty ? null : Vehicle.fromMap(rows.first),
          );
        });
  }

  Future<void> createProfile(String profileId, Vehicle vehicle) async {
    await db.execute(
      'INSERT INTO driver_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    await _insertVehicle(profileId, vehicle);
  }

  Future<void> addVehicle(Vehicle vehicle) =>
      _insertVehicle(vehicle.driverProfileId, vehicle);

  Future<void> _insertVehicle(String driverProfileId, Vehicle vehicle) {
    return db.execute(
      '''
      INSERT INTO vehicle (id, driver_profile_id, vehicle_type, plate_number, max_load_kg, preferred_min_load_kg)
      VALUES (uuid(), ?, ?, ?, ?, ?)
      ''',
      [
        driverProfileId,
        vehicle.vehicleType,
        vehicle.plateNumber,
        vehicle.maxLoadKg,
        vehicle.preferredMinLoadKg,
      ],
    );
  }

  Future<void> updateVehicle(String vehicleId, Vehicle vehicle) {
    return db.execute(
      'UPDATE vehicle SET vehicle_type = ?, plate_number = ?, max_load_kg = ?, preferred_min_load_kg = ? WHERE id = ?',
      [
        vehicle.vehicleType,
        vehicle.plateNumber,
        vehicle.maxLoadKg,
        vehicle.preferredMinLoadKg,
        vehicleId,
      ],
    );
  }
}
