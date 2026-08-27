import '../../../core/local_db/powersync.dart'; // exposes `db`
import '../../../core/local_db/repository.dart';
import '../../../models/driver_profile.dart';

class DriverProfileService {
  final _vehicles = Repository<Vehicle>(
    table: 'vehicle',
    fromMap: Vehicle.fromMap,
    toInsertMap: (v) => v.toInsertMap(),
  );

  Future<bool> hasProfile(String profileId) async {
    final row = await db.getOptional(
      'SELECT id FROM driver_profile WHERE profile_id = ?',
      [profileId],
    );
    return row != null;
  }

  Stream<DriverProfile?> watchOwnProfile(String profileId) {
    return _vehicles
        .watchAll(
          where: 'driver_profile_id = ?',
          parameters: [profileId],
          orderBy: 'id',
          limit: 1,
        )
        .map(
          (vehicles) => DriverProfile(
            profileId: profileId,
            primaryVehicle: vehicles.isEmpty ? null : vehicles.first,
          ),
        );
  }

  /// driver_profile is a marker row (profile_id only, no other columns
  /// worth modeling) — not worth a full `Repository<T>`, so it stays a
  /// direct db call, same as before.
  Future<void> createProfile(String profileId, Vehicle vehicle) async {
    await db.execute(
      'INSERT INTO driver_profile (id, profile_id) VALUES (?, ?)',
      [profileId, profileId],
    );
    await _vehicles.insertGenerated(vehicle);
  }

  Future<void> addVehicle(Vehicle vehicle) =>
      _vehicles.insertGenerated(vehicle);

  Future<void> updateVehicle(String vehicleId, Vehicle vehicle) =>
      _vehicles.update(vehicleId, vehicle);
}
