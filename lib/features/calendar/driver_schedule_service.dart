import '../../core/supabase/client.dart';
import '../../models/driver_task.dart';

class DriverScheduleService {
  Stream<Map<DateTime, List<DriverTask>>> watchTasksForDriver(
    String driverProfileId,
  ) async* {
    Future<Map<DateTime, List<DriverTask>>> fetchTasks() async {
      final response = await supabase
          .from('delivery_assignment')
          .select('''
            delivery_id,
            delivery:delivery_id (
              id,
              status,
              assigned_at,
              farmer_display_name,
              buyer_display_name,
              order:order_id (
                total_amount,
                order_date,
                order_item (
                  crop:crop_id (
                    name
                  )
                )
              )
            )
          ''')
          .eq('driver_profile_id', driverProfileId)
          .eq('is_current', true);

      // ignore: avoid_print
      print('📦 [DriverScheduleService] Raw rows for driver $driverProfileId: ${response.length}');
      final byDay = <DateTime, List<DriverTask>>{};
      for (final raw in (response as List)) {
        final d = raw['delivery'] as Map<String, dynamic>?;
        if (d == null) continue;
        final o = d['order'] as Map<String, dynamic>?;
        final items = (o?['order_item'] as List?) ?? [];
        final cropNamesSet = <String>{};
        for (final item in items) {
          final crop = (item as Map<String, dynamic>)['crop'] as Map<String, dynamic>?;
          if (crop != null && crop['name'] != null) {
            cropNamesSet.add(crop['name'] as String);
          }
        }

        final row = {
          'delivery_id': d['id'],
          'status': d['status'],
          'assigned_at': d['assigned_at'],
          'farmer_display_name': d['farmer_display_name'],
          'buyer_display_name': d['buyer_display_name'],
          'total_amount': o?['total_amount'],
          'order_date': o?['order_date'],
          'crop_names': cropNamesSet.join(', '),
        };

        final day = DriverTask.dayOf(row);
        // ignore: avoid_print
        print('  ➜ Task found for date: $day | Order Date: ${o?['order_date']} | Delivery ID: ${d['id']}');
        byDay.putIfAbsent(day, () => []).add(DriverTask.fromDeliveryRow(row));
      }
      return byDay;
    }

    yield await fetchTasks();
  }
}
