import '../../core/local_db/repository.dart';
import '../../core/supabase/client.dart';
import 'recurring_order_models.dart';

/// Recurring orders are **server-authoritative** (online-only, like the
/// marketplace). The PowerSync streams for these tables are invalid (they
/// join on a dropped `buyer_profile_id`), so local rows don't come back
/// after a re-login — reading or writing them locally loses data. Every
/// read here goes to Supabase, and every write is a single atomic RPC (see
/// migration 20261018110000_recurring_orders_server_authoritative.sql).
class RecurringOrderService {
  final Repository<RecurringSchedule> _scheduleRepo;

  RecurringOrderService()
    : _scheduleRepo = Repository<RecurringSchedule>(
        table: 'recurring_schedule',
        fromMap: RecurringSchedule.fromMap,
        toInsertMap: (value) => value.toInsertMap(),
      );

  Stream<List<RecurringScheduleSummary>> watchScheduleSummaries(
    String buyerProfileId,
  ) {
    return supabase
        .from('recurring_schedule')
        .stream(primaryKey: ['id'])
        .eq('buyer_profile_id', buyerProfileId)
        .order('created_at', ascending: false)
        .asyncMap(_loadScheduleSummaries);
  }

  Future<List<RecurringScheduleSummary>> _loadScheduleSummaries(
    List<Map<String, dynamic>> scheduleRows,
  ) async {
    if (scheduleRows.isEmpty) return [];

    final scheduleIds = scheduleRows.map((row) => row['id'] as String).toList();
    final orderRows = await supabase
        .from('recurring_order')
        .select('id, schedule_id, day_of_week, recurring_order_item(id)')
        .inFilter('schedule_id', scheduleIds);

    final daysBySchedule = <String, Set<int>>{};
    final itemCountBySchedule = <String, int>{};
    for (final row in orderRows) {
      final scheduleId = row['schedule_id'] as String;
      final day = row['day_of_week'];
      if (day is num) {
        daysBySchedule.putIfAbsent(scheduleId, () => <int>{}).add(day.toInt());
      }
      final items = row['recurring_order_item'];
      itemCountBySchedule[scheduleId] =
          (itemCountBySchedule[scheduleId] ?? 0) +
          (items is List ? items.length : 0);
    }

    return scheduleRows.map((row) {
      final schedule = RecurringSchedule.fromMap(row);
      final days = (daysBySchedule[schedule.id] ?? <int>{}).toList()..sort();
      return RecurringScheduleSummary(
        schedule: schedule,
        daysOfWeek: days,
        totalItems: itemCountBySchedule[schedule.id] ?? 0,
      );
    }).toList();
  }

  /// One schedule's delivery days with their items and crop details,
  /// straight from the server (so it's never empty after a re-login).
  Future<List<RecurringDayDetail>> fetchScheduleDays(String scheduleId) async {
    final rows = await supabase
        .from('recurring_order')
        .select(
          'id, day_of_week, frequency, next_run_at, delivery_address, status, '
          'processing_status, last_error, last_processed_date, '
          'recurring_order_item(id, crop_id, quantity_kg, preferred_farmer_id, '
          'crop(name, category, fallback_image_url))',
        )
        .eq('schedule_id', scheduleId)
        .order('day_of_week');
    return rows.map(RecurringDayDetail.fromMap).toList();
  }

  /// Creates ([scheduleId] null) or replaces a schedule in one transaction.
  /// If a delivery day is tomorrow, the server places that order
  /// immediately — see [RecurringSaveResult.tomorrow].
  Future<RecurringSaveResult> saveSchedule({
    String? scheduleId,
    required String label,
    required String frequency,
    required Map<String, dynamic> deliveryAddress,
    required Map<int, List<RecurringItemInput>> itemsByDay,
    DateTime? endDate,
  }) async {
    final result = await supabase.rpc(
      'save_recurring_schedule',
      params: {
        'p_schedule_id': scheduleId,
        'p_label': label,
        'p_frequency': frequency,
        'p_end_date': endDate?.toUtc().toIso8601String(),
        'p_delivery_address': deliveryAddress,
        'p_days': [
          for (final entry in itemsByDay.entries)
            if (entry.value.isNotEmpty)
              {
                'day_of_week': entry.key,
                'items': [for (final item in entry.value) item.toJson()],
              },
        ],
      },
    );
    return RecurringSaveResult.fromMap(result as Map<String, dynamic>);
  }

  /// Pause, or resume (which also places tomorrow's order if one is due).
  Future<RecurringSaveResult> setScheduleStatus(
    String scheduleId, {
    required bool active,
  }) async {
    final result = await supabase.rpc(
      'set_recurring_schedule_status',
      params: {
        'p_schedule_id': scheduleId,
        'p_status': active ? 'active' : 'paused',
      },
    );
    final map = result as Map<String, dynamic>;
    return RecurringSaveResult.fromMap({...map, 'schedule_id': scheduleId});
  }

  /// Skips this delivery day's next occurrence; returns the new date.
  Future<DateTime?> skipNextOrder(String recurringOrderId) async {
    final result = await supabase.rpc(
      'skip_next_recurring_order',
      params: {'p_recurring_order_id': recurringOrderId},
    );
    return result is String ? DateTime.tryParse(result) : null;
  }

  Future<void> deleteSchedule(String scheduleId) async {
    // Server first; recurring child rows cascade from recurring_schedule.
    await supabase.from('recurring_schedule').delete().eq('id', scheduleId);
    // Drop any stale local mirror row too (harmless if absent).
    await _scheduleRepo.delete(scheduleId);
  }
}
