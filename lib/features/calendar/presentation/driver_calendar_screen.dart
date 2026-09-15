import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_header.dart';
import '../../../models/driver_task.dart';
import '../../../models/profile.dart';
import '../driver_schedule_service.dart';

/// Short month-name translation keys, indexed 1..12 (index 0 unused),
/// so the week-range/day headers never hardcode English month names.
const _monthShortKeys = [
  '',
  'month_short_jan',
  'month_short_feb',
  'month_short_mar',
  'month_short_apr',
  'month_short_may',
  'month_short_jun',
  'month_short_jul',
  'month_short_aug',
  'month_short_sep',
  'month_short_oct',
  'month_short_nov',
  'month_short_dec',
];

/// Driver's "Weekly Schedule" calendar tab — mirrors Weekly_Schedule.png:
/// a week strip with prev/next navigation, a task-load dot under each
/// day, and the selected day's delivery/pickup list below.
///
/// Uses the shared [AppHeader] (brand mark, notification bell, avatar)
/// and sits inside the shared [AppNavShell] bottom nav, so both stay in
/// sync with every other role tab automatically. Fully responsive (a
/// centered, width-capped column on tablets/desktop, edge-to-edge on
/// phones) and theme/locale-aware throughout — no hardcoded colors or
/// user-facing strings.
///
/// Backed by [DriverScheduleService], which streams the driver's real
/// assigned deliveries from PowerSync (see that file's doc comment) —
/// [sampleDriverTasksFor] is kept only as an empty-state/demo fallback
/// for other call sites, not used here anymore.
class DriverCalendarScreen extends StatefulWidget {
  final Profile profile;

  const DriverCalendarScreen({super.key, required this.profile});

  @override
  State<DriverCalendarScreen> createState() => _DriverCalendarScreenState();
}

class _DriverCalendarScreenState extends State<DriverCalendarScreen> {
  late DateTime _weekStart;
  late DateTime _selectedDay;
  final _scheduleService = DriverScheduleService();
  late final Stream<Map<DateTime, List<DriverTask>>> _tasksByDay =
      _scheduleService.watchTasksForDriver(widget.profile.id);

  static const _weekdayShortKeys = [
    'day_short_mon',
    'day_short_tue',
    'day_short_wed',
    'day_short_thu',
    'day_short_fri',
    'day_short_sat',
    'day_short_sun',
  ];

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _selectedDay = today;
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _shiftWeek(int deltaWeeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
      _selectedDay = _weekStart;
    });
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width < 600 ? width : 560.0;
    final hPad = width < 360 ? 12.0 : 16.0;

    final weekDays = List.generate(7, (i) => _weekStart.add(Duration(days: i)));

    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      body: SafeArea(
        child: StreamBuilder<Map<DateTime, List<DriverTask>>>(
          stream: _tasksByDay,
          builder: (context, snapshot) {
            final rawTasksByDay = snapshot.data ?? const {};
            final tasksByDay = <DateTime, List<DriverTask>>{};
            for (final entry in rawTasksByDay.entries) {
              final d = entry.key;
              final key = DateTime(d.year, d.month, d.day);
              tasksByDay.putIfAbsent(key, () => []).addAll(entry.value);
            }
            final tasks = tasksByDay[_selectedDay] ?? const <DriverTask>[];

            // Debug log
            // ignore: avoid_print
            print(
              '📅 [Calendar Debug] Driver ID: ${widget.profile.id} | Selected Date: ${_selectedDay.toIso8601String().split('T').first} | Assigned Tasks: ${tasks.length} | All Dates With Tasks: ${tasksByDay.keys.map((k) => k.toIso8601String().split('T').first).toList()}',
            );

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
                  children: [
                    Text(
                      'weekly_schedule'.tr(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'manage_deliveries_pickups'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _WeekCard(
                      weekDays: weekDays,
                      selectedDay: _selectedDay,
                      weekdayShortKeys: _weekdayShortKeys,
                      tasksByDay: tasksByDay,
                      onPrevWeek: () => _shiftWeek(-1),
                      onNextWeek: () => _shiftWeek(1),
                      onSelectDay: _selectDay,
                    ),
                    const SizedBox(height: 24),
                    _DayTasksHeader(day: _selectedDay, taskCount: tasks.length),
                    const SizedBox(height: 12),
                    if (tasks.isEmpty)
                      _EmptyDayCard(theme: theme)
                    else
                      ...tasks.map(
                        (task) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _TaskCard(task: task),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final List<DateTime> weekDays;
  final DateTime selectedDay;
  final List<String> weekdayShortKeys;
  final Map<DateTime, List<DriverTask>> tasksByDay;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final ValueChanged<DateTime> onSelectDay;

  const _WeekCard({
    required this.weekDays,
    required this.selectedDay,
    required this.weekdayShortKeys,
    required this.tasksByDay,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onSelectDay,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// "Load" dot color per day, driven by that day's real assigned
  /// tasks — mirrors the amber/green/gray dots in Weekly_Schedule.png.
  Color? _dotColor(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    final key = DateTime(day.year, day.month, day.day);
    final tasks = tasksByDay[key] ?? const <DriverTask>[];
    if (tasks.isEmpty) return null;
    final hasPickup = tasks.any((t) => t.type == DriverTaskType.pickup);
    final allDone = tasks.every((t) => t.isDone);
    if (allDone) return theme.colorScheme.onSurface.withValues(alpha: 0.35);
    if (hasPickup) return const Color(0xFFFFC107); // warnAmber
    return theme.colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = weekDays.first;
    final last = weekDays.last;
    final sameMonth = first.month == last.month;
    final firstMonth = _monthShortKeys[first.month].tr();
    final lastMonth = _monthShortKeys[last.month].tr();
    final rangeLabel = sameMonth
        ? '$firstMonth ${first.day} - ${last.day}'
        : '$firstMonth ${first.day} - $lastMonth ${last.day}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'previous_week'.tr(),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrevWeek,
                ),
                Text(
                  rangeLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: 'next_week'.tr(),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onNextWeek,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < weekDays.length; i++)
                  Expanded(
                    child: _DayCell(
                      day: weekDays[i],
                      isSelected: _isSameDay(weekDays[i], selectedDay),
                      isToday: _isSameDay(weekDays[i], _dateOnlyNow()),
                      weekdayLabel: weekdayShortKeys[i].tr(),
                      dotColor: _dotColor(context, weekDays[i]),
                      onTap: () => onSelectDay(weekDays[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DateTime _dateOnlyNow() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final String weekdayLabel;
  final Color? dotColor;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.weekdayLabel,
    required this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              weekdayLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? theme.colorScheme.primary : null,
                border: isToday && !isSelected
                    ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 6,
              width: 6,
              child: dotColor == null
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTasksHeader extends StatelessWidget {
  final DateTime day;
  final int taskCount;

  const _DayTasksHeader({required this.day, required this.taskCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${_monthShortKeys[day.month].tr()} ${day.day}, ${day.year}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Chip(
          label: Text('n_tasks'.tr(namedArgs: {'count': '$taskCount'})),
          backgroundColor: theme.colorScheme.secondary,
          side: BorderSide.none,
          labelStyle: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  final ThemeData theme;

  const _EmptyDayCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 36,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'no_tasks_today'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DriverTask task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPickup = task.type == DriverTaskType.pickup;
    final accent = task.isDone
        ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
        : isPickup
        ? const Color(0xFFFFC107) // warnAmber
        : theme.colorScheme.primary;

    // titleArgs/subtitleArgs hold raw data (place names, numbers) that
    // get interpolated into the translated sentence — they're never
    // translated themselves, since a farm or market name isn't a
    // localizable string.
    final resolvedTitle = task.titleKey.tr(namedArgs: task.titleArgs);
    final resolvedSubtitle = task.subtitleKey.tr(namedArgs: task.subtitleArgs);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 4),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isPickup
                          ? Icons.agriculture_outlined
                          : Icons.local_shipping_outlined,
                      color: task.isDone
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                          : accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                resolvedTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: task.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: task.isDone
                                      ? theme.colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        )
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (task.isDone)
                              _StatusPill.done(theme)
                            else
                              _StatusPill.time(theme, task.time, context),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          resolvedSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        if (task.thumbnailEmojis.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final emoji in task.thumbnailEmojis)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (!task.isDone) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('details'.tr()),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_forward, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const _StatusPill._({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  factory _StatusPill.done(ThemeData theme) => _StatusPill._(
    label: 'done'.tr(),
    background: theme.colorScheme.secondary,
    foreground: theme.colorScheme.primary,
    icon: Icons.check_circle_outline,
  );

  factory _StatusPill.time(ThemeData theme, TimeOfDay time, BuildContext ctx) =>
      _StatusPill._(
        label: time.format(ctx),
        background: theme.colorScheme.secondary,
        foreground: theme.colorScheme.onSurface,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
