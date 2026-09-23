import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../recurring_order_models.dart';
import '../../recurring_order_service.dart';
import 'create_recurring_schedule_screen.dart';
import 'recurring_schedule_detail_screen.dart';

class RecurringScheduleListWidget extends StatefulWidget {
  final String buyerProfileId;

  const RecurringScheduleListWidget({super.key, required this.buyerProfileId});

  @override
  State<RecurringScheduleListWidget> createState() =>
      _RecurringScheduleListWidgetState();
}

class _RecurringScheduleListWidgetState
    extends State<RecurringScheduleListWidget> {
  final RecurringOrderService service = RecurringOrderService();
  final Set<String> _deletedScheduleIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RecurringScheduleSummary>>(
      stream: service.watchScheduleSummaries(widget.buyerProfileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final summaries = (snapshot.data ?? [])
            .where(
              (summary) => !_deletedScheduleIds.contains(summary.schedule.id),
            )
            .toList();
        if (summaries.isEmpty) {
          return _EmptyState(buyerProfileId: widget.buyerProfileId);
        }

        return Stack(
          children: [
            ListView.builder(
              padding: const EdgeInsets.only(
                top: 16,
                bottom: 80,
                left: 16,
                right: 16,
              ),
              itemCount: summaries.length,
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return _ScheduleCard(
                  summary: summary,
                  service: service,
                  onDeleted: () {
                    if (mounted) {
                      setState(() {
                        _deletedScheduleIds.add(summary.schedule.id);
                      });
                    }
                  },
                );
              },
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                onPressed: () =>
                    _navigateToCreate(context, widget.buyerProfileId),
                icon: const Icon(Icons.add),
                label: const Text('New Schedule'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final RecurringScheduleSummary summary;
  final RecurringOrderService service;
  final VoidCallback onDeleted;

  const _ScheduleCard({
    required this.summary,
    required this.service,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final schedule = summary.schedule;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RecurringScheduleDetailScreen(scheduleId: schedule.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      schedule.label,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _StatusPill(status: schedule.status),
                  const SizedBox(width: 8),
                  _QuickActionMenu(
                    schedule: schedule,
                    service: service,
                    onDeleted: onDeleted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDays(summary.daysOfWeek),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.shopping_basket_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${summary.totalItems} item${summary.totalItems == 1 ? '' : 's'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDays(List<int> days) {
    if (days.isEmpty) return 'No days';
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days.map((d) => dayNames[d % 7]).join(' · ');
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green.shade200 : Colors.amber.shade200,
        ),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green.shade700 : Colors.amber.shade700,
        ),
      ),
    );
  }
}

class _QuickActionMenu extends StatelessWidget {
  final RecurringSchedule schedule;
  final RecurringOrderService service;
  final VoidCallback onDeleted;

  const _QuickActionMenu({
    required this.schedule,
    required this.service,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = schedule.status == 'active';
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (val) async {
        if (val == 'pause') {
          await service.pauseSchedule(schedule.id);
        } else if (val == 'resume') {
          await service.resumeSchedule(schedule.id, updatedNextRunAtMap: {});
        } else if (val == 'edit') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateRecurringScheduleScreen(
                buyerProfileId: schedule.buyerProfileId,
                existingScheduleId: schedule.id,
              ),
            ),
          );
        } else if (val == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Schedule?'),
              content: const Text(
                'Are you sure you want to delete this schedule? This will not affect past orders.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            try {
              await service.deleteSchedule(schedule.id);
              onDeleted();
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not delete schedule: $error'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          }
        }
      },
      itemBuilder: (context) => [
        if (isActive) const PopupMenuItem(value: 'pause', child: Text('Pause')),
        if (!isActive)
          const PopupMenuItem(value: 'resume', child: Text('Resume')),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String buyerProfileId;
  const _EmptyState({required this.buyerProfileId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Scheduled Orders',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Automate your inventory restocking by setting up recurring orders. They will be placed automatically each week.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _navigateToCreate(context, buyerProfileId),
              icon: const Icon(Icons.add),
              label: const Text('Create your first schedule'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _navigateToCreate(BuildContext context, String buyerProfileId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          CreateRecurringScheduleScreen(buyerProfileId: buyerProfileId),
    ),
  );
}
