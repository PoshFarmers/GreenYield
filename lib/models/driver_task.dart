import 'package:flutter/material.dart';

/// Kind of stop on a driver's schedule. Drives icon/colour choice on
/// [DriverCalendarScreen] — see `driver_task_visuals.dart`... (kept
/// inline below since it's only used there).
enum DriverTaskType { delivery, pickup }

/// Number formatter for `order_total`'s `{amount}` placeholder —
/// deliberately simple (no currency lib dependency) since the value is
/// already an LKR total from `orders.total_amount`.
String _formatAmount(double amount) => amount.toStringAsFixed(2);

/// A single delivery/pickup task shown on the driver's weekly calendar.
///
/// No backend table for driver scheduling exists yet (there's no
/// `driver_task`/`delivery` model anywhere in `lib/models`), so this is
/// deliberately a plain, storage-agnostic class fed by
/// [sampleDriverTasksFor] placeholder data — matches Weekly_Schedule.png
/// pixel-for-pixel. Swap the sample generator for a real
/// PowerSync-backed stream once that table lands; the widget tree in
/// [DriverCalendarScreen] doesn't need to change, just the data source.
@immutable
class DriverTask {
  final String id;
  final DriverTaskType type;

  /// Translation key for the title, e.g. `delivery_to` -> "Delivery to
  /// {place}". [titleArgs] fills named placeholders; place/farm/market
  /// names are raw data, not translated themselves.
  final String titleKey;
  final Map<String, String> titleArgs;
  final String subtitleKey;
  final Map<String, String> subtitleArgs;
  final TimeOfDay time;
  final bool isDone;
  final List<String> thumbnailEmojis;

  const DriverTask({
    required this.id,
    required this.type,
    required this.titleKey,
    this.titleArgs = const {},
    required this.subtitleKey,
    this.subtitleArgs = const {},
    required this.time,
    this.isDone = false,
    this.thumbnailEmojis = const [],
  });

  /// Builds a real task from one row of
  /// `DriverScheduleService.watchTasksForDriver`'s joined query — one
  /// row per delivery assigned to this driver, carrying the farmer/buyer
  /// display names cached on `delivery` at assignment time (see
  /// `20260913090000_notify_and_driver_order_access.sql`) plus a
  /// comma-joined crop-name summary from that order's items.
  ///
  /// A delivery is a single stop pair (pickup then dropoff); until it's
  /// picked up it shows as a pickup task, then as a delivery task until
  /// it's marked delivered.
  factory DriverTask.fromDeliveryRow(Map<String, dynamic> row) {
    final status = row['status'] as String? ?? 'assigned';
    final isPickupPhase = status == 'assigned';
    final cropSummary = (row['crop_names'] as String?)?.trim();
    final total = (row['total_amount'] as num?)?.toDouble();

    final assignedAt = DateTime.parse(row['assigned_at'] as String).toLocal();

    return DriverTask(
      id: row['delivery_id'] as String,
      type: isPickupPhase ? DriverTaskType.pickup : DriverTaskType.delivery,
      titleKey: isPickupPhase ? 'pickup_at' : 'delivery_to',
      titleArgs: {
        'place':
            (isPickupPhase
                ? row['farmer_display_name'] as String?
                : row['buyer_display_name'] as String?) ??
            '',
      },
      subtitleKey: cropSummary != null && cropSummary.isNotEmpty
          ? 'crop_summary'
          : 'order_total',
      subtitleArgs: cropSummary != null && cropSummary.isNotEmpty
          ? {'crop': cropSummary}
          : {'amount': total == null ? '' : _formatAmount(total)},
      time: TimeOfDay.fromDateTime(assignedAt),
      isDone: status == 'delivered',
    );
  }

  /// The calendar day this task belongs on — the buyer's requested
  /// `order_date` (see `20260914000000_add_order_date.sql`), not the
  /// day the order happened to be assigned to this driver. Falls back
  /// to `assigned_at`'s day for any older/synced row that predates the
  /// `order_date` column.
  static DateTime dayOf(Map<String, dynamic> row) {
    final orderDate = row['order_date'] as String?;
    if (orderDate != null && orderDate.isNotEmpty) {
      final parts = orderDate.split('T').first.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
      final parsed = DateTime.parse(orderDate).toLocal();
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final assignedAt = DateTime.parse(row['assigned_at'] as String).toLocal();
    return DateTime(assignedAt.year, assignedAt.month, assignedAt.day);
  }
}

/// Deterministic placeholder schedule keyed by weekday (1 = Monday .. 7
/// = Sunday), so the same date always shows the same demo tasks instead
/// of re-randomizing on every rebuild.
Map<int, List<DriverTask>> _sampleWeek() => {
  1: [
    const DriverTask(
      id: 'mon-1',
      type: DriverTaskType.delivery,
      titleKey: 'delivery_to',
      titleArgs: {'place': 'Riverside Grocers'},
      subtitleKey: 'route_duration',
      subtitleArgs: {'route': 'A', 'minutes': '30'},
      time: TimeOfDay(hour: 9, minute: 15),
    ),
  ],
  2: [
    const DriverTask(
      id: 'tue-1',
      type: DriverTaskType.pickup,
      titleKey: 'pickup_at',
      titleArgs: {'place': 'Green Valley Farm'},
      subtitleKey: 'district_duration',
      subtitleArgs: {'district': 'North District', 'minutes': '25'},
      time: TimeOfDay(hour: 11, minute: 0),
    ),
    const DriverTask(
      id: 'tue-2',
      type: DriverTaskType.delivery,
      titleKey: 'delivery_to',
      titleArgs: {'place': 'Central Market'},
      subtitleKey: 'route_duration',
      subtitleArgs: {'route': 'B', 'minutes': '40'},
      time: TimeOfDay(hour: 15, minute: 30),
      isDone: true,
    ),
  ],
  3: [
    const DriverTask(
      id: 'wed-1',
      type: DriverTaskType.delivery,
      titleKey: 'delivery_to',
      titleArgs: {'place': 'Central Market'},
      subtitleKey: 'route_duration',
      subtitleArgs: {'route': 'A', 'minutes': '45'},
      time: TimeOfDay(hour: 8, minute: 0),
      thumbnailEmojis: ['🥬', '🍅'],
    ),
    const DriverTask(
      id: 'wed-2',
      type: DriverTaskType.pickup,
      titleKey: 'pickup_at',
      titleArgs: {'place': 'Sunrise Farm'},
      subtitleKey: 'district_pallets_crop',
      subtitleArgs: {
        'district': 'North District',
        'minutes': '20',
        'pallets': '2',
        'crop': 'Organic Corn',
      },
      time: TimeOfDay(hour: 10, minute: 30),
    ),
    const DriverTask(
      id: 'wed-3',
      type: DriverTaskType.delivery,
      titleKey: 'delivery_to',
      titleArgs: {'place': 'BioShop'},
      subtitleKey: 'route_completed',
      subtitleArgs: {'route': 'B'},
      time: TimeOfDay(hour: 13, minute: 0),
      isDone: true,
    ),
  ],
  4: [
    const DriverTask(
      id: 'thu-1',
      type: DriverTaskType.pickup,
      titleKey: 'pickup_at',
      titleArgs: {'place': 'Hilltop Orchards'},
      subtitleKey: 'district_duration',
      subtitleArgs: {'district': 'East District', 'minutes': '35'},
      time: TimeOfDay(hour: 9, minute: 45),
    ),
  ],
  5: [
    const DriverTask(
      id: 'fri-1',
      type: DriverTaskType.delivery,
      titleKey: 'delivery_to',
      titleArgs: {'place': 'Lakeside Buyers Co-op'},
      subtitleKey: 'route_duration',
      subtitleArgs: {'route': 'A', 'minutes': '50'},
      time: TimeOfDay(hour: 14, minute: 0),
    ),
  ],
  6: [],
  7: [],
};

/// Returns the placeholder tasks for [date], keyed off its weekday.
List<DriverTask> sampleDriverTasksFor(DateTime date) {
  final week = _sampleWeek();
  return List.unmodifiable(week[date.weekday] ?? const []);
}
