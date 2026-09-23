import 'package:flutter/material.dart';

import '../../../../core/local_db/powersync.dart';
import '../../../../core/supabase/client.dart';
import '../../../../core/widgets/media_image.dart';
import '../../../../models/notification_item.dart';
import '../../recurring_order_models.dart';
import '../../recurring_order_service.dart';

class RecurringScheduleDetailScreen extends StatefulWidget {
  final String scheduleId;

  const RecurringScheduleDetailScreen({super.key, required this.scheduleId});

  @override
  State<RecurringScheduleDetailScreen> createState() =>
      _RecurringScheduleDetailScreenState();
}

class _RecurringScheduleDetailScreenState
    extends State<RecurringScheduleDetailScreen> {
  final RecurringOrderService _service = RecurringOrderService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Details')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('recurring_schedule')
            .stream(primaryKey: ['id'])
            .eq('id', widget.scheduleId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('Schedule not found.'));
          }

          final scheduleRow = snapshot.data!.first;
          final schedule = RecurringSchedule.fromMap(scheduleRow);
          final isActive = schedule.status == 'active';
          final theme = Theme.of(context);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      schedule.label,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusPill(status: schedule.status),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  if (isActive) {
                    await _service.pauseSchedule(schedule.id);
                  } else {
                    await _service.resumeSchedule(
                      schedule.id,
                      updatedNextRunAtMap: {},
                    );
                  }
                },
                icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                label: Text(isActive ? 'Pause Schedule' : 'Resume Schedule'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isActive ? Colors.orange : Colors.green,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Items',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _ScheduleItemsList(scheduleId: schedule.id),
              const SizedBox(height: 32),
              Text(
                'History',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _ScheduleHistoryList(scheduleId: schedule.id),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleItemsList extends StatelessWidget {
  final String scheduleId;

  const _ScheduleItemsList({required this.scheduleId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.watch(
        '''
        SELECT 
          o.id as order_id,
          o.day_of_week, 
          o.next_run_at,
          oi.quantity_kg,
          c.name as crop_name,
          c.fallback_image_url
        FROM recurring_order o
        JOIN recurring_order_item oi ON oi.recurring_order_id = o.id
        JOIN crop c ON c.id = oi.crop_id
        WHERE o.schedule_id = ?
        ORDER BY o.day_of_week ASC
      ''',
        parameters: [scheduleId],
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) return const Text('No items.');

        // Group by day
        final Map<int, List<Map<String, dynamic>>> grouped = {};
        for (var row in rows) {
          final day = row['day_of_week'] as int;
          grouped.putIfAbsent(day, () => []).add(row);
        }

        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        return Column(
          children: grouped.entries.map((e) {
            final dayIndex = e.key;
            final items = e.value;
            final dayName = days[dayIndex % 7];
            final orderId = items.first['order_id'] as String;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ExpansionTile(
                title: Text(
                  dayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                initiallyExpanded: true,
                children: [
                  ...items.map((item) {
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: MediaImage(
                          path: item['fallback_image_url'] as String?,
                          bucket: 'crop-photos',
                          public: true,
                          placeholder: const Icon(Icons.image),
                        ),
                      ),
                      title: Text(item['crop_name'] as String),
                      trailing: Text(
                        '${item['quantity_kg']} kg',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await RecurringOrderService().skipNextOrder(orderId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Skipped next occurrence.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip Next'),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ScheduleHistoryList extends StatelessWidget {
  final String scheduleId;

  const _ScheduleHistoryList({required this.scheduleId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.watch(
        'SELECT * FROM notification WHERE source_table = ? AND source_id = ? ORDER BY created_at DESC',
        parameters: ['recurring_schedule', scheduleId],
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Text(
            'No history yet.',
            style: TextStyle(color: Colors.grey),
          );
        }

        return Column(
          children: rows.map((row) {
            final notification = NotificationItem.fromMap(row);

            Color iconColor;
            IconData iconData;
            String outcomeText;

            if (notification.type == 'recurring_fulfilled') {
              iconColor = Colors.green;
              iconData = Icons.check_circle;
              outcomeText = 'Placed';
            } else if (notification.type == 'recurring_skipped_low_balance') {
              iconColor = Colors.red;
              iconData = Icons.account_balance_wallet;
              outcomeText = 'Skipped - Low Balance';
            } else {
              iconColor = Colors.orange;
              iconData = Icons.warning;
              outcomeText = 'Unfulfilled';
            }

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(iconData, color: iconColor),
              title: Text(
                outcomeText,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${notification.createdAt.day}/${notification.createdAt.month}/${notification.createdAt.year}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.green.shade200 : Colors.amber.shade200,
        ),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green.shade700 : Colors.amber.shade700,
        ),
      ),
    );
  }
}
