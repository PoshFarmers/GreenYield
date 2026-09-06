import 'package:flutter/material.dart';

/// Kind of stop on a driver's schedule. Drives icon/colour choice on
/// [DriverCalendarScreen] — see `driver_task_visuals.dart`... (kept
/// inline below since it's only used there).
enum DriverTaskType { delivery, pickup }

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
