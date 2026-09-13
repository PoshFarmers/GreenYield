class Vehicle {
  final String? id;
  final String driverProfileId;
  final String vehicleType; // three_wheeler|van|lorry|truck|tractor
  final String plateNumber;

  /// Total seating/passenger capacity of the vehicle. Stored in the
  /// existing `max_load_kg` column — the column name is a legacy
  /// holdover from the cargo-logistics schema, but the value itself is
  /// a plain capacity count, so no migration is needed to repurpose it
  /// for the passenger-ride "Vehicle Capacity" field.
  final double maxLoadKg;

  /// Preferred maximum passenger count for a ride, stored in
  /// `preferred_min_load_kg` for the same reason as [maxLoadKg] above.
  final double? preferredMinLoadKg;

  const Vehicle({
    this.id,
    required this.driverProfileId,
    required this.vehicleType,
    required this.plateNumber,
    required this.maxLoadKg,
    this.preferredMinLoadKg,
  });

  /// Vehicle Capacity, as a whole passenger count for display/inputs.
  int get capacity => maxLoadKg.round();

  /// Preferred Capacity, as a whole passenger count for display/inputs.
  int? get preferredCapacity => preferredMinLoadKg?.round();

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

/// A single resolved point on the map: the free-text address the driver
/// sees, plus (when available) the geocoded coordinates and a stable
/// place identifier so the same point can be reused elsewhere in the
/// app (map previews, distance/duration estimates, re-centering a
/// picker) instead of re-geocoding the address string every time.
///
/// [latitude]/[longitude]/[placeId] are all nullable because a driver
/// can type a free-text address that hasn't resolved to a place yet —
/// the address is still saved, just without the structured extras.
class LocationPoint {
  final String address;
  final double? latitude;
  final double? longitude;
  final String? placeId;

  const LocationPoint({
    required this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  bool get isEmpty => address.trim().isEmpty;
  bool get hasCoordinates => latitude != null && longitude != null;

  static const empty = LocationPoint(address: '');

  LocationPoint copyWith({
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
    bool clearCoordinates = false,
  }) {
    return LocationPoint(
      address: address ?? this.address,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      placeId: clearCoordinates ? null : (placeId ?? this.placeId),
    );
  }
}

class RoutePreference {
  final String? id;
  final String driverProfileId;
  final LocationPoint origin;
  final LocationPoint destination;
  final RouteDirection direction;
  final int activeDaysMask;
  final bool isActive;
  final double? distanceKm;
  final int? durationMinutes;

  const RoutePreference({
    this.id,
    required this.driverProfileId,
    required this.origin,
    required this.destination,
    this.direction = RouteDirection.both,
    this.activeDaysMask = 0,
    this.isActive = true,
    this.distanceKm,
    this.durationMinutes,
  });

  // Convenience accessors — most read-only UI (saved-route cards, list
  // rows) only ever needs the address strings.
  String get originLocation => origin.address;
  String get destinationLocation => destination.address;

  Set<String> get activeDayKeys => activeDaysKeysFromMask(activeDaysMask);

  RoutePreference copyWith({
    LocationPoint? origin,
    LocationPoint? destination,
    RouteDirection? direction,
    int? activeDaysMask,
    bool? isActive,
    double? distanceKm,
    int? durationMinutes,
  }) {
    return RoutePreference(
      id: id,
      driverProfileId: driverProfileId,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      direction: direction ?? this.direction,
      activeDaysMask: activeDaysMask ?? this.activeDaysMask,
      isActive: isActive ?? this.isActive,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  factory RoutePreference.fromMap(Map<String, dynamic> map) {
    return RoutePreference(
      id: map['id'] as String,
      driverProfileId: map['driver_profile_id'] as String,
      origin: LocationPoint(
        address: map['origin_location'] as String,
        latitude: (map['origin_lat'] as num?)?.toDouble(),
        longitude: (map['origin_lng'] as num?)?.toDouble(),
        placeId: map['origin_place_id'] as String?,
      ),
      destination: LocationPoint(
        address: map['destination_location'] as String,
        latitude: (map['destination_lat'] as num?)?.toDouble(),
        longitude: (map['destination_lng'] as num?)?.toDouble(),
        placeId: map['destination_place_id'] as String?,
      ),
      direction: routeDirectionFromDb((map['direction'] as String?) ?? 'both'),
      activeDaysMask: (map['active_days'] as num?)?.toInt() ?? 0,
      isActive: ((map['is_active'] as num?)?.toInt() ?? 1) == 1,
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'driver_profile_id': driverProfileId,
    'origin_location': origin.address,
    'origin_lat': origin.latitude,
    'origin_lng': origin.longitude,
    'origin_place_id': origin.placeId,
    'destination_location': destination.address,
    'destination_lat': destination.latitude,
    'destination_lng': destination.longitude,
    'destination_place_id': destination.placeId,
    'direction': routeDirectionToDb(direction),
    'active_days': activeDaysMask,
    'is_active': isActive ? 1 : 0,
    'distance_km': distanceKm,
    'duration_minutes': durationMinutes,
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
