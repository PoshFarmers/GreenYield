import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../../core/widgets/app_text_field.dart';
import '../../../../../models/driver_profile.dart';

/// In-memory, not-yet-saved route being edited by the user. Carries
/// [existingId] when editing a row that already exists in
/// `driver_route_preference`, so the caller knows insert vs update.
class RouteDraft {
  final String? existingId;
  final TextEditingController originController;
  final TextEditingController destinationController;
  RouteDirection direction;
  Set<String> activeDays;

  RouteDraft({
    this.existingId,
    String origin = '',
    String destination = '',
    this.direction = RouteDirection.both,
    Set<String>? activeDays,
  }) : originController = TextEditingController(text: origin),
       destinationController = TextEditingController(text: destination),
       activeDays = activeDays ?? <String>{};

  // Coordinates/place id resolved for the current text, if any — kept
  // alongside the controllers so a draft started from an existing
  // RoutePreference (which may already have structured location data)
  // doesn't lose it just from being re-edited as plain text.
  LocationPoint _originPoint = LocationPoint.empty;
  LocationPoint _destinationPoint = LocationPoint.empty;

  factory RouteDraft.fromRoutePreference(RoutePreference route) {
    final draft = RouteDraft(
      existingId: route.id,
      origin: route.originLocation,
      destination: route.destinationLocation,
      direction: route.direction,
      activeDays: route.activeDayKeys,
    );
    draft._originPoint = route.origin;
    draft._destinationPoint = route.destination;
    return draft;
  }

  /// True once both endpoints are filled in — used to decide whether a
  /// draft is worth persisting (empty trailing drafts are dropped).
  bool get isFilled =>
      originController.text.trim().isNotEmpty &&
      destinationController.text.trim().isNotEmpty;

  RoutePreference toRoutePreference(String driverProfileId) {
    return RoutePreference(
      id: existingId,
      driverProfileId: driverProfileId,
      origin: _originPoint.copyWith(
        address: originController.text.trim(),
        // Coordinates only stay valid if the address wasn't retyped.
        clearCoordinates: _originPoint.address != originController.text.trim(),
      ),
      destination: _destinationPoint.copyWith(
        address: destinationController.text.trim(),
        clearCoordinates:
            _destinationPoint.address != destinationController.text.trim(),
      ),
      direction: direction,
      activeDaysMask: activeDaysMaskFromKeys(activeDays),
    );
  }

  void dispose() {
    originController.dispose();
    destinationController.dispose();
  }
}

/// Editable card matching the "Preferred Routes" designs: start/end
/// location fields, an outbound/both/return direction toggle, and a row
/// of weekday chips. Used both inline during account setup and on the
/// dedicated route-setup screen reached from the profile.
class RouteDraftCard extends StatefulWidget {
  final RouteDraft draft;
  final VoidCallback? onRemove;
  final ValueChanged<RouteDraft>? onChanged;

  const RouteDraftCard({
    super.key,
    required this.draft,
    this.onRemove,
    this.onChanged,
  });

  @override
  State<RouteDraftCard> createState() => _RouteDraftCardState();
}

class _RouteDraftCardState extends State<RouteDraftCard> {
  void _notify() => widget.onChanged?.call(widget.draft);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;

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
          if (widget.onRemove != null)
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'remove_route'.tr(),
                onPressed: widget.onRemove,
              ),
            ),
          _EndpointRow(
            icon: Icons.trip_origin,
            iconColor: theme.colorScheme.primary,
            label: 'start_location'.tr(),
            controller: draft.originController,
            onChanged: (_) => _notify(),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 9),
            child: SizedBox(
              height: 18,
              child: VerticalDivider(width: 18, thickness: 1.4),
            ),
          ),
          _EndpointRow(
            icon: Icons.location_on,
            iconColor: theme.colorScheme.tertiary,
            label: 'end_location'.tr(),
            controller: draft.destinationController,
            onChanged: (_) => _notify(),
          ),
          const SizedBox(height: 16),
          Text('direction'.tr(), style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _DirectionToggle(
            value: draft.direction,
            onChanged: (value) {
              setState(() => draft.direction = value);
              _notify();
            },
          ),
          const SizedBox(height: 16),
          Text('active_days'.tr(), style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in weekdayKeys)
                _WeekdayToggleChip(
                  dayKey: day,
                  selected: draft.activeDays.contains(day),
                  onTap: () {
                    setState(() {
                      if (draft.activeDays.contains(day)) {
                        draft.activeDays.remove(day);
                      } else {
                        draft.activeDays.add(day);
                      }
                    });
                    _notify();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _EndpointRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: AppTextField(
            label: label,
            controller: controller,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _DirectionToggle extends StatelessWidget {
  final RouteDirection value;
  final ValueChanged<RouteDirection> onChanged;

  const _DirectionToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = const [
      RouteDirection.outbound,
      RouteDirection.both,
      RouteDirection.returnTrip,
    ];
    final labels = {
      RouteDirection.outbound: 'outbound'.tr(),
      RouteDirection.both: 'both'.tr(),
      RouteDirection.returnTrip: 'return_trip'.tr(),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        return ToggleButtons(
          isSelected: options.map((o) => o == value).toList(),
          onPressed: (index) => onChanged(options[index]),
          borderRadius: BorderRadius.circular(10),
          constraints: BoxConstraints(
            minHeight: 40,
            minWidth: (constraints.maxWidth - 4) / options.length,
          ),
          children: [for (final o in options) Text(labels[o]!)],
        );
      },
    );
  }
}

class _WeekdayToggleChip extends StatelessWidget {
  final String dayKey;
  final bool selected;
  final VoidCallback onTap;

  const _WeekdayToggleChip({
    required this.dayKey,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
        ),
        child: Text(
          'day_letter_$dayKey'.tr(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Small pill used to render the recurring-day summary on read-only
/// cards (profile section, saved-routes list) — distinct from the
/// tappable [_WeekdayToggleChip] above.
class RouteDayPill extends StatelessWidget {
  final String dayKey;

  const RouteDayPill({super.key, required this.dayKey});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'day_short_$dayKey'.tr().toUpperCase(),
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}
