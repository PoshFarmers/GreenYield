import 'dart:developer' as developer;

import '../../core/supabase/client.dart';
import '../../models/driver_stop.dart';

/// Backs [DriverHomeScreen] — today's pickup/dropoff stops and the
/// "Start Route" action. Reads go straight to Supabase (via the
/// `get_driver_today_stops` RPC) rather than through the PowerSync
/// mirror, since the map/list need fresh cross-user data (farmer &
/// buyer names, phones, coordinates) every time the driver opens the
/// screen — a plain refresh-on-demand fits that better than a
/// long-lived local stream.
class DriverHomeService {
  const DriverHomeService();

  Future<List<DriverStop>> fetchTodayStops(String driverProfileId) async {
    final data = await supabase.rpc(
      'get_driver_today_stops',
      params: {'p_driver_id': driverProfileId},
    );
    final rows = (data as List<dynamic>? ?? []);
    return rows
        .map((e) => DriverStop.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Marks the driver as having started today's route and notifies
  /// every buyer/farmer on [orderIds] via `start_driver_shift`.
  Future<void> startShift(List<String> orderIds) async {
    if (orderIds.isEmpty) return;
    developer.log(
      'Calling start_driver_shift RPC — orders: $orderIds',
      name: 'GreenYield.DriverHomeService',
    );
    await supabase.rpc('start_driver_shift', params: {'p_order_ids': orderIds});
  }

  /// Driver confirms pickup at the farmer: moves the delivery from
  /// `assigned` straight through to `in_transit` (picked up and
  /// already on the way to the buyer), which is what the single
  /// "Picked Up" button on the home screen represents.
  Future<void> confirmPickup(String deliveryId) async {
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'picked_up'},
    );
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'in_transit'},
    );
  }

  /// Driver confirms delivery at the buyer: moves the delivery to `delivered`.
  Future<void> confirmDelivery(String deliveryId) async {
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'delivered'},
    );
  }

  /// Records the driver's real-time GPS location in `delivery_tracking`
  /// so buyers and farmers can see the driver's live truck location.
  Future<void> recordDriverLocation({
    required List<String> activeDeliveryIds,
    required double latitude,
    required double longitude,
    double? speedKmh,
    double? heading,
  }) async {
    if (activeDeliveryIds.isEmpty) return;
    for (final deliveryId in activeDeliveryIds) {
      try {
        await supabase.from('delivery_tracking').insert({
          'delivery_id': deliveryId,
          'location_point': 'POINT($longitude $latitude)',
          if (speedKmh != null) 'speed_kmh': speedKmh,
          if (heading != null) 'heading': heading,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (e) {
        developer.log(
          'Failed to record driver delivery ping: $e',
          name: 'GreenYield.DriverHomeService',
        );
      }
    }
  }
}
