import 'package:flutter/material.dart';

import '../../../../core/local_db/powersync.dart';
import '../../../../core/supabase/client.dart';
import '../../../../core/widgets/app_secondary_header.dart';
import '../../../../core/widgets/media_image.dart';
import '../../../../models/notification_item.dart';
import '../../recurring_order_models.dart';
import '../../recurring_order_service.dart';
import 'recurring_messages.dart';

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
      appBar: const AppSecondaryHeader(title: 'Schedule Details'),
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
                onPressed: () => setScheduleActiveWithFeedback(
                  context,
                  _service,
                  schedule.id,
                  active: !isActive,
                ),
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
              // Keyed on status so pausing/resuming (which moves next
              // delivery dates) reloads the list.
              _ScheduleItemsList(
                key: ValueKey('${schedule.id}:${schedule.status}'),
                scheduleId: schedule.id,
                service: _service,
              ),
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

/// Items per delivery day, read from the server: the local mirror of the
/// recurring tables is empty after a re-login (invalid sync streams),
/// which is why this used to show "No items." after logging back in.
class _ScheduleItemsList extends StatefulWidget {
  final String scheduleId;
  final RecurringOrderService service;

  const _ScheduleItemsList({
    super.key,
    required this.scheduleId,
    required this.service,
  });

  @override
  State<_ScheduleItemsList> createState() => _ScheduleItemsListState();
}

class _ScheduleItemsListState extends State<_ScheduleItemsList> {
  late Future<List<RecurringDayDetail>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.fetchScheduleDays(widget.scheduleId);
  }

  Future<void> _skip(RecurringDayDetail day) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final next = await widget.service.skipNextOrder(day.recurringOrderId);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            next == null
                ? 'Skipped the next delivery.'
                : 'Skipped. Next delivery: ${_formatDate(next)}.',
          ),
        ),
      );
      if (mounted) setState(_load);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't skip. Check your connection and try again."),
        ),
      );
    }
  }

  static String _formatDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  /// Status of the next delivery, in buyer terms.
  (String, Color)? _statusChip(RecurringDayDetail day) {
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final next = DateTime(
      day.nextDelivery.year,
      day.nextDelivery.month,
      day.nextDelivery.day,
    );
    return switch (day.processingStatus) {
      'awaiting_funds' => ('Waiting for wallet funds', Colors.red),
      'awaiting_inventory' => ('Waiting for stock', Colors.orange),
      _ when next == tomorrow => ('Order placed', Colors.green),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<RecurringDayDetail>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Row(
            children: [
              const Expanded(
                child: Text("Couldn't load items. Check your connection."),
              ),
              TextButton(
                onPressed: () => setState(_load),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        final daysWithItems = (snapshot.data ?? const <RecurringDayDetail>[])
            .where((d) => d.items.isNotEmpty)
            .toList();
        if (daysWithItems.isEmpty) return const Text('No items.');

        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        return Column(
          children: daysWithItems.map((day) {
            final dayName = dayNames[day.dayOfWeek % 7];
            final chip = _statusChip(day);

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
                subtitle: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      day.status == 'active'
                          ? 'Next: ${_formatDate(day.nextDelivery)}'
                          : 'Paused',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (chip != null && day.status == 'active')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: chip.$2.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          chip.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: chip.$2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                initiallyExpanded: true,
                children: [
                  ...day.items.map((item) {
                    final fallbackUrl = item.fallbackImageUrl;
                    final category = item.cropCategory;
                    final isFruit = category?.toLowerCase() == 'fruit';
                    final categoryIcon = Icon(
                      isFruit ? Icons.apple : Icons.eco,
                      size: 24,
                      color: theme.colorScheme.primary,
                    );

                    final bucket =
                        (fallbackUrl != null &&
                            (fallbackUrl.contains('crop-fallback') ||
                                fallbackUrl.startsWith('crops/') ||
                                !fallbackUrl.contains('/')))
                        ? 'crop-fallback-images'
                        : 'crop-photos';

                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: MediaImage(
                            path: fallbackUrl,
                            bucket: bucket,
                            public: true,
                            placeholder: Container(
                              color: theme.colorScheme.surfaceContainerHigh,
                              alignment: Alignment.center,
                              child: categoryIcon,
                            ),
                          ),
                        ),
                      ),
                      title: Text(item.cropName),
                      trailing: Text(
                        '${_formatKg(item.quantityKg)} kg',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                  if (day.status == 'active')
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: OutlinedButton.icon(
                        onPressed: () => _skip(day),
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

String _formatKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);

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
