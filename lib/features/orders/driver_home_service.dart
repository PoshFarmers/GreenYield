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

  /// Driver confirms dropoff at the buyer: completes the delivery.
  Future<void> confirmDropoff(String deliveryId) async {
    await supabase.rpc(
      'transition_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_new_status': 'delivered'},
    );
  }
}
