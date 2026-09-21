import 'package:flutter/foundation.dart';

@immutable
class LiveTrackingPerson {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double? latitude;
  final double? longitude;

  const LiveTrackingPerson({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory LiveTrackingPerson.fromMap(Map<String, dynamic> map) {
    return LiveTrackingPerson(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }
}

@immutable
class LiveTrackingDriver {
  final String id;
  final String name;
  final String? phone;
  final double? latitude;
  final double? longitude;
  final double? speedKmh;
  final double? heading;
  final DateTime? recordedAt;

  const LiveTrackingDriver({
    required this.id,
    required this.name,
    this.phone,
    this.latitude,
    this.longitude,
    this.speedKmh,
    this.heading,
    this.recordedAt,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory LiveTrackingDriver.fromMap(Map<String, dynamic> map) {
    return LiveTrackingDriver(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      speedKmh: (map['speed_kmh'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      recordedAt: map['recorded_at'] != null
          ? DateTime.tryParse(map['recorded_at'] as String)
          : null,
    );
  }
}

@immutable
class LiveOrderTracking {
  final String orderId;
  final String status;
  final DateTime? orderDate;
  final DateTime? placedAt;
  final bool isPickedUp;
  final LiveTrackingDriver? driver;
  final LiveTrackingPerson? farmer;
  final LiveTrackingPerson? buyer;

  const LiveOrderTracking({
    required this.orderId,
    required this.status,
    this.orderDate,
    this.placedAt,
    required this.isPickedUp,
    this.driver,
    this.farmer,
    this.buyer,
  });

  /// Check if the tracking button should be visible/active.
  /// Visible until the order is completed or cancelled.
  bool get isOrderDay {
    return status != 'delivered' &&
        status != 'completed' &&
        status != 'cancelled';
  }


  factory LiveOrderTracking.fromMap(Map<String, dynamic> map) {
    return LiveOrderTracking(
      orderId: map['order_id'] as String? ?? '',
      status: map['status'] as String? ?? '',
      orderDate: map['order_date'] != null
          ? DateTime.tryParse(map['order_date'] as String)
          : null,
      placedAt: map['placed_at'] != null
          ? DateTime.tryParse(map['placed_at'] as String)
          : null,
      isPickedUp: map['is_picked_up'] as bool? ?? false,
      driver: map['driver'] != null
          ? LiveTrackingDriver.fromMap(map['driver'] as Map<String, dynamic>)
          : null,
      farmer: map['farmer'] != null
          ? LiveTrackingPerson.fromMap(map['farmer'] as Map<String, dynamic>)
          : null,
      buyer: map['buyer'] != null
          ? LiveTrackingPerson.fromMap(map['buyer'] as Map<String, dynamic>)
          : null,
    );
  }
}
