import 'package:flutter/material.dart';

/// Kind of stop — pickup at the farmer, or dropoff at the buyer.
enum DriverStopType { pickup, dropoff }

/// One pickup or dropoff stop on the driver's today route, as returned
/// by the `get_driver_today_stops` RPC (see
/// `20260916210000_driver_home_today_stops.sql`). A single order
/// contributes a pickup stop while its delivery is still `assigned`,
/// then a dropoff stop once it's been picked up.
@immutable
class DriverStop {
  final DriverStopType type;
  final String orderId;
  final String deliveryId;

  /// Postgres `order_status` enum value, e.g. `assigned`, `picked_up`.
  final String orderStatus;

  /// Postgres `delivery_status` enum value.
  final String deliveryStatus;

  final String? counterpartName;
  final String? counterpartPhone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? cropNames;
  final double totalAmount;
  final DateTime? orderDate;

  const DriverStop({
    required this.type,
    required this.orderId,
    required this.deliveryId,
    required this.orderStatus,
    required this.deliveryStatus,
    this.counterpartName,
    this.counterpartPhone,
    this.address,
    this.latitude,
    this.longitude,
    this.cropNames,
    this.totalAmount = 0,
    this.orderDate,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// This particular stop (not the whole order) is done: a pickup is
  /// done once the delivery has moved past `assigned`; a dropoff is
  /// done once it's `delivered`.
  bool get isDone => type == DriverStopType.pickup
      ? deliveryStatus != 'assigned'
      : deliveryStatus == 'delivered';

  /// Short human-readable order id: GY-XXXXXX — matches
  /// `OrderSummary.displayId` / `OrderDetail.displayId` elsewhere in
  /// the app.
  String get displayOrderId =>
      'GY-${orderId.replaceAll('-', '').substring(0, 6).toUpperCase()}';

  factory DriverStop.fromMap(Map<String, dynamic> row) {
    return DriverStop(
      type: (row['stop_type'] as String?) == 'dropoff'
          ? DriverStopType.dropoff
          : DriverStopType.pickup,
      orderId: row['order_id'] as String,
      deliveryId: row['delivery_id'] as String,
      orderStatus: row['order_status'] as String? ?? 'placed',
      deliveryStatus: row['delivery_status'] as String? ?? 'assigned',
      counterpartName: row['counterpart_name'] as String?,
      counterpartPhone: row['counterpart_phone'] as String?,
      address: row['address'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      cropNames: row['crop_names'] as String?,
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0,
      orderDate: row['order_date'] != null
          ? DateTime.tryParse(row['order_date'] as String)
          : null,
    );
  }
}
