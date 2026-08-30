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

/// Days of week as a bitmask, bit 0 = Monday .. bit 6 = Sunday, matching
/// the `driver_route_preference.active_days` smallint column.
enum RouteDirection { outbound, returnTrip, both }

RouteDirection routeDirectionFromDb(String value) {
  switch (value) {
    case 'outbound':
      return RouteDirection.outbound;
    case 'return':
      return RouteDirection.returnTrip;
    default:
      return RouteDirection.both;
  }
}

String routeDirectionToDb(RouteDirection direction) {
  switch (direction) {
    case RouteDirection.outbound:
      return 'outbound';
    case RouteDirection.returnTrip:
      return 'return';
    case RouteDirection.both:
      return 'both';
  }
}

/// Short weekday keys, Monday-first, used both as the bitmask index order
/// and as translation-key suffixes (`day_short_mon`, ...).
const weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

int activeDaysMaskFromKeys(Set<String> keys) {
  var mask = 0;
  for (var i = 0; i < weekdayKeys.length; i++) {
    if (keys.contains(weekdayKeys[i])) mask |= (1 << i);
  }
  return mask;
}

Set<String> activeDaysKeysFromMask(int mask) {
  final keys = <String>{};
  for (var i = 0; i < weekdayKeys.length; i++) {
    if ((mask & (1 << i)) != 0) keys.add(weekdayKeys[i]);
  }
  return keys;
}

class RoutePreference {
  final String? id;
  final String driverProfileId;
  final String originLocation;
  final String destinationLocation;
  final RouteDirection direction;
  final int activeDaysMask;
  final bool isActive;

  const RoutePreference({
    this.id,
    required this.driverProfileId,
    required this.originLocation,
    required this.destinationLocation,
    this.direction = RouteDirection.both,
    this.activeDaysMask = 0,
    this.isActive = true,
  });

  Set<String> get activeDayKeys => activeDaysKeysFromMask(activeDaysMask);

  RoutePreference copyWith({
    String? originLocation,
    String? destinationLocation,
    RouteDirection? direction,
    int? activeDaysMask,
    bool? isActive,
  }) {
    return RoutePreference(
      id: id,
      driverProfileId: driverProfileId,
      originLocation: originLocation ?? this.originLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      direction: direction ?? this.direction,
      activeDaysMask: activeDaysMask ?? this.activeDaysMask,
      isActive: isActive ?? this.isActive,
    );
  }

  factory RoutePreference.fromMap(Map<String, dynamic> map) {
    return RoutePreference(
      id: map['id'] as String,
      driverProfileId: map['driver_profile_id'] as String,
      originLocation: map['origin_location'] as String,
      destinationLocation: map['destination_location'] as String,
      direction: routeDirectionFromDb((map['direction'] as String?) ?? 'both'),
      activeDaysMask: (map['active_days'] as num?)?.toInt() ?? 0,
      isActive: ((map['is_active'] as num?)?.toInt() ?? 1) == 1,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'driver_profile_id': driverProfileId,
    'origin_location': originLocation,
    'destination_location': destinationLocation,
    'direction': routeDirectionToDb(direction),
    'active_days': activeDaysMask,
    'is_active': isActive ? 1 : 0,
  };
}

class DriverProfile {
  final String profileId;
  final Vehicle? primaryVehicle;
  final List<RoutePreference> routePreferences;

  const DriverProfile({
    required this.profileId,
    this.primaryVehicle,
    this.routePreferences = const [],
  });
}
