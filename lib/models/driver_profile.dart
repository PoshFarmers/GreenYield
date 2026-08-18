class Vehicle {
  final String? id;
  final String driverProfileId;
  final String vehicleType; // three_wheeler|van|lorry|truck|tractor
  final String plateNumber;
  final double maxLoadKg;
  final double? preferredMinLoadKg;

  const Vehicle({
    this.id,
    required this.driverProfileId,
    required this.vehicleType,
    required this.plateNumber,
    required this.maxLoadKg,
    this.preferredMinLoadKg,
  });

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] as String,
      driverProfileId: map['driver_profile_id'] as String,
      vehicleType: map['vehicle_type'] as String,
      plateNumber: map['plate_number'] as String,
      maxLoadKg: (map['max_load_kg'] as num).toDouble(),
      preferredMinLoadKg: map['preferred_min_load_kg'] == null
          ? null
          : (map['preferred_min_load_kg'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'driver_profile_id': driverProfileId,
    'vehicle_type': vehicleType,
    'plate_number': plateNumber,
    'max_load_kg': maxLoadKg,
    if (preferredMinLoadKg != null) 'preferred_min_load_kg': preferredMinLoadKg,
  };
}

class DriverProfile {
  final String profileId;
  final Vehicle? primaryVehicle;

  const DriverProfile({required this.profileId, this.primaryVehicle});
}
