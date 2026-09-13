import '../../core/local_db/powersync.dart'; // exposes `db`
import '../../models/driver_task.dart';

/// Backs [DriverCalendarScreen] with the driver's real assigned
/// deliveries (see `assign_nearest_driver` /
/// `20260913090000_notify_and_driver_order_access.sql`) instead of the
/// placeholder [sampleDriverTasksFor] data.
///
/// One row per delivery currently assigned to this driver, joined
/// against that delivery's order for the total and against
/// `order_item`/`crop` for a comma-joined crop-name summary. All three
/// tables (`delivery`, `delivery_assignment`, `orders`, `order_item`,
/// `crop`) are PowerSync-synced, so this is a local SQLite query and
/// updates live as assignments/status changes sync in.
class DriverScheduleService {
  /// Watches every task across all days (cheap: a driver's full
  /// schedule is small), grouped by calendar day for
  /// [DriverCalendarScreen] to slice per selected day.
  Stream<Map<DateTime, List<DriverTask>>> watchTasksForDriver(
    String driverProfileId,
  ) {
    return db
        .watch(
          '''
          SELECT
            d.id AS delivery_id,
            d.status,
            d.assigned_at,
            d.farmer_display_name,
            d.buyer_display_name,
            o.total_amount,
            (
              SELECT GROUP_CONCAT(DISTINCT c.name)
              FROM order_item oi
              JOIN crop c ON c.id = oi.crop_id
              WHERE oi.order_id = d.order_id
            ) AS crop_names
          FROM delivery d
          JOIN delivery_assignment da ON da.delivery_id = d.id AND da.is_current = 1
          JOIN orders o ON o.id = d.order_id
          WHERE da.driver_profile_id = ?
          ORDER BY d.assigned_at ASC
          ''',
          parameters: [driverProfileId],
        )
        .map((rows) {
          final byDay = <DateTime, List<DriverTask>>{};
          for (final row in rows) {
            final day = DriverTask.dayOf(row);
            byDay
                .putIfAbsent(day, () => [])
                .add(DriverTask.fromDeliveryRow(row));
          }
          return byDay;
        });
  }
}
