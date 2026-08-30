import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/driver_profile.dart';
import '../driver_profile_service.dart';
import 'driver_route_setup_screen.dart';
import 'widgets/route_draft_editor.dart';

/// Lists every preferred route saved by the driver, with pause/resume,
/// edit, and delete actions — matches Manage_Routes.png. Reached from
/// the profile screen's "Preferred Routes" section (edit icon, or the
/// section itself when there's at least one route).
class DriverManageRoutesScreen extends StatefulWidget {
  final String driverProfileId;

  const DriverManageRoutesScreen({super.key, required this.driverProfileId});

  @override
  State<DriverManageRoutesScreen> createState() =>
      _DriverManageRoutesScreenState();
}

class _DriverManageRoutesScreenState extends State<DriverManageRoutesScreen> {
  final _service = DriverProfileService();

  void _openEditor({RoutePreference? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverRouteSetupScreen(
          driverProfileId: widget.driverProfileId,
          existingRoute: existing,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(RoutePreference route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_route'.tr()),
        content: Text('confirm_delete_route'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'delete'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && route.id != null) {
      await _service.deleteRoute(route.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = width < 480 ? width : 480.0;
    final hPad = width < 360 ? 16.0 : 20.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('saved_routes'.tr()),
        actions: [
          IconButton(
            tooltip: 'help'.tr(),
            icon: const Icon(Icons.help_outline),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'add_another_route'.tr(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: StreamBuilder<List<RoutePreference>>(
              stream: _service.watchRoutes(widget.driverProfileId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final routes = snapshot.data!;
                return ListView(
                  padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 96),
                  children: [
                    Text(
                      'manage_recurring_deliveries'.tr(),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'edit_or_remove_routes_hint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (routes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'no_routes_added'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      for (final route in routes) ...[
                        _SavedRouteCard(
                          route: route,
                          onEdit: () => _openEditor(existing: route),
                          onDelete: () => _confirmDelete(route),
                          onToggleActive: (active) =>
                              _service.setRouteActive(route, active),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedRouteCard extends StatelessWidget {
  final RoutePreference route;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleActive;

  const _SavedRouteCard({
    required this.route,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeDays = weekdayKeys.where(route.activeDayKeys.contains);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: route.isActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (route.isActive ? 'active' : 'paused').tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: route.isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                    case 'toggle':
                      onToggleActive(!route.isActive);
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text('edit_route'.tr())),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      (route.isActive ? 'pause_route' : 'resume_route').tr(),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'delete'.tr(),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${route.originLocation} → ${route.destinationLocation}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (activeDays.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final day in activeDays) RouteDayPill(dayKey: day)],
            ),
          const Divider(height: 24),
          Row(
            children: [
              Text(
                _directionLabel(route.direction).tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              TextButton(onPressed: onEdit, child: Text('edit_route'.tr())),
            ],
          ),
        ],
      ),
    );
  }

  String _directionLabel(RouteDirection direction) {
    switch (direction) {
      case RouteDirection.outbound:
        return 'outbound';
      case RouteDirection.returnTrip:
        return 'return_trip';
      case RouteDirection.both:
        return 'outbound_and_return';
    }
  }
}
