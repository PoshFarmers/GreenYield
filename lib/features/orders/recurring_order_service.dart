import 'package:uuid/uuid.dart';

import '../../core/local_db/repository.dart';
import '../../core/local_db/powersync.dart';
import '../../core/supabase/client.dart';
import 'recurring_order_models.dart';

class RecurringOrderService {
  final Repository<RecurringSchedule> _scheduleRepo;
  final Repository<RecurringOrder> _orderRepo;
  final Repository<RecurringOrderItem> _itemRepo;

  RecurringOrderService()
    : _scheduleRepo = Repository<RecurringSchedule>(
        table: 'recurring_schedule',
        fromMap: RecurringSchedule.fromMap,
        toInsertMap: (value) => value.toInsertMap(),
      ),
      _orderRepo = Repository<RecurringOrder>(
        table: 'recurring_order',
        fromMap: RecurringOrder.fromMap,
        toInsertMap: (value) => value.toInsertMap(),
      ),
      _itemRepo = Repository<RecurringOrderItem>(
        table: 'recurring_order_item',
        fromMap: RecurringOrderItem.fromMap,
        toInsertMap: (value) => value.toInsertMap(),
      );

  Stream<List<RecurringSchedule>> watchSchedules(String buyerProfileId) {
    return _scheduleRepo.watchAll(
      where: 'buyer_profile_id = ?',
      parameters: [buyerProfileId],
      orderBy: 'created_at DESC',
    );
  }

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
        .select('id, schedule_id, day_of_week')
        .inFilter('schedule_id', scheduleIds);

    final orderIds = orderRows.map((row) => row['id'] as String).toList();
    final itemCountBySchedule = <String, int>{};
    if (orderIds.isNotEmpty) {
      final itemRows = await supabase
          .from('recurring_order_item')
          .select('recurring_order_id')
          .inFilter('recurring_order_id', orderIds);
      final scheduleByOrderId = {
        for (final row in orderRows)
          row['id'] as String: row['schedule_id'] as String,
      };
      for (final row in itemRows) {
        final scheduleId = scheduleByOrderId[row['recurring_order_id']];
        if (scheduleId != null) {
          itemCountBySchedule[scheduleId] =
              (itemCountBySchedule[scheduleId] ?? 0) + 1;
        }
      }
    }

    final daysBySchedule = <String, Set<int>>{};
    for (final row in orderRows) {
      final scheduleId = row['schedule_id'] as String;
      final day = row['day_of_week'];
      if (day is num) {
        daysBySchedule.putIfAbsent(scheduleId, () => <int>{}).add(day.toInt());
      }
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

  Stream<List<RecurringOrder>> watchOrdersForSchedule(String scheduleId) {
    return _orderRepo.watchAll(
      where: 'schedule_id = ?',
      parameters: [scheduleId],
      orderBy: 'day_of_week ASC',
    );
  }

  Stream<List<RecurringOrderItem>> watchItemsForOrder(String orderId) {
    return _itemRepo.watchAll(
      where: 'recurring_order_id = ?',
      parameters: [orderId],
    );
  }

  Future<void> createSchedule({
    required String buyerProfileId,
    required String label,
    required List<RecurringOrder> orders,
    required Map<String, List<RecurringOrderItem>> itemsByOrderId,
    DateTime? endDate,
  }) async {
    final scheduleId = const Uuid().v4();
    final now = DateTime.now();

    final schedule = RecurringSchedule(
      id: scheduleId,
      buyerProfileId: buyerProfileId,
      label: label,
      status: 'active',
      createdAt: now,
      endDate: endDate,
    );

    // Write locally via PowerSync — shows in UI instantly
    await _scheduleRepo.insert(scheduleId, schedule);

    // Also write directly to Supabase so the RPC can run immediately
    // (PowerSync upload is async; we can't wait for it before calling RPC).
    // The connector uses upsert, so when PowerSync uploads the local write
    // it will just no-op against the already-existing Supabase row.
    await supabase.from('recurring_schedule').upsert({
      'id': scheduleId,
      'buyer_profile_id': buyerProfileId,
      'label': label,
      'status': 'active',
      'created_at': now.toUtc().toIso8601String(),
      if (endDate != null) 'end_date': endDate.toUtc().toIso8601String(),
    });

    for (var order in orders) {
      final orderId = const Uuid().v4();

      final finalOrder = RecurringOrder(
        id: orderId,
        scheduleId: scheduleId,
        frequency: order.frequency,
        dayOfWeek: order.dayOfWeek,
        nextRunAt: order.nextRunAt,
        deliveryAddress: order.deliveryAddress,
        deliveryLocation: order.deliveryLocation,
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );

      // Write locally
      await _orderRepo.insert(orderId, finalOrder);

      // Write to Supabase directly
      await supabase.from('recurring_order').upsert({
        'id': orderId,
        'schedule_id': scheduleId,
        'frequency': order.frequency,
        'day_of_week': order.dayOfWeek,
        'next_run_at': order.nextRunAt.toUtc().toIso8601String(),
        if (order.deliveryAddress != null)
          'delivery_address': order.deliveryAddress,
        if (order.deliveryLocation != null)
          'delivery_location': order.deliveryLocation,
        'status': 'active',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });

      final items = itemsByOrderId[order.id] ?? [];
      for (var item in items) {
        final itemId = const Uuid().v4();

        final finalItem = RecurringOrderItem(
          id: itemId,
          recurringOrderId: orderId,
          cropId: item.cropId,
          quantityKg: item.quantityKg,
          preferredFarmerId: item.preferredFarmerId,
          createdAt: now,
        );

        // Write locally
        await _itemRepo.insert(itemId, finalItem);

        // Write to Supabase directly
        await supabase.from('recurring_order_item').upsert({
          'id': itemId,
          'recurring_order_id': orderId,
          'crop_id': item.cropId,
          'quantity_kg': item.quantityKg,
          if (item.preferredFarmerId != null)
            'preferred_farmer_id': item.preferredFarmerId,
          'created_at': now.toUtc().toIso8601String(),
        });
      }

      if (_isTomorrow(finalOrder.nextRunAt, now)) {
        await fulfillOrderNow(orderId);
      }
    }
  }

  bool _isTomorrow(DateTime occurrence, DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return occurrence.year == tomorrow.year &&
        occurrence.month == tomorrow.month &&
        occurrence.day == tomorrow.day;
  }

  /// Fulfills tomorrow's occurrence directly via Supabase RPC.
  Future<void> fulfillOrderNow(String recurringOrderId) async {
    final result = await supabase.rpc(
      'fulfill_recurring_order',
      params: {'p_recurring_order_id': recurringOrderId},
    );
    if (result is Map) {
      final status = result['status']?.toString();
      if (status == 'awaiting_funds' || status == 'awaiting_inventory') {
        throw StateError(
          'Tomorrow’s recurring order is $status. '
          'The schedule was saved and will be retried.',
        );
      }
      if (status == 'skipped' && result['reason'] != 'already_processed') {
        throw StateError(
          'Recurring order was not placed: ${result['reason'] ?? 'unknown reason'}',
        );
      }
    }
  }

  Future<List<String>> updateSchedule({
    required String scheduleId,
    required String label,
    required List<RecurringOrder> orders,
    required Map<String, List<RecurringOrderItem>> itemsByOrderId,
    DateTime? endDate,
  }) async {
    final insertedOrderIds = <String>[];

    await db.execute(
      'UPDATE recurring_schedule SET label = ?, end_date = ? WHERE id = ?',
      [label, endDate?.toUtc().toIso8601String(), scheduleId],
    );

    await db.execute('DELETE FROM recurring_order WHERE schedule_id = ?', [
      scheduleId,
    ]);

    for (var order in orders) {
      final orderId = const Uuid().v4();
      final finalOrder = RecurringOrder(
        id: orderId,
        scheduleId: scheduleId,
        frequency: order.frequency,
        dayOfWeek: order.dayOfWeek,
        nextRunAt: order.nextRunAt,
        deliveryAddress: order.deliveryAddress,
        deliveryLocation: order.deliveryLocation,
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _orderRepo.insert(orderId, finalOrder);
      insertedOrderIds.add(orderId);

      final items = itemsByOrderId[order.id] ?? [];
      for (var item in items) {
        final itemId = const Uuid().v4();
        final finalItem = RecurringOrderItem(
          id: itemId,
          recurringOrderId: orderId,
          cropId: item.cropId,
          quantityKg: item.quantityKg,
          preferredFarmerId: item.preferredFarmerId,
          createdAt: DateTime.now(),
        );

        await _itemRepo.insert(itemId, finalItem);
      }
    }

    return insertedOrderIds;
  }

  Future<void> skipNextOrder(String orderId) async {
    await db.execute('SELECT skip_next_recurring_order(?)', [orderId]);
  }

  Future<void> pauseSchedule(String scheduleId) async {
    await db.execute('UPDATE recurring_schedule SET status = ? WHERE id = ?', [
      'paused',
      scheduleId,
    ]);
    await db.execute(
      'UPDATE recurring_order SET status = ? WHERE schedule_id = ?',
      ['paused', scheduleId],
    );
  }

  Future<void> resumeSchedule(
    String scheduleId, {
    required Map<String, DateTime> updatedNextRunAtMap,
  }) async {
    await db.execute('UPDATE recurring_schedule SET status = ? WHERE id = ?', [
      'active',
      scheduleId,
    ]);
    await db.execute(
      'UPDATE recurring_order SET status = ? WHERE schedule_id = ?',
      ['active', scheduleId],
    );

    for (final entry in updatedNextRunAtMap.entries) {
      final orderId = entry.key;
      final nextRunAt = entry.value;
      await db.execute(
        'UPDATE recurring_order SET next_run_at = ? WHERE id = ?',
        [nextRunAt.toUtc().toIso8601String(), orderId],
      );
    }
  }

  Future<void> deleteSchedule(String scheduleId) async {
    // Delete on the server first. The schedule list is server-backed and
    // recurring child rows cascade from recurring_schedule in Postgres.
    await supabase.from('recurring_schedule').delete().eq('id', scheduleId);

    // Remove the local mirror immediately as well; this also clears any
    // pending PowerSync delete operation for the same row.
    await _scheduleRepo.delete(scheduleId);
  }
}
