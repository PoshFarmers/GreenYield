import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../../core/widgets/route_map_picker.dart';
import '../../../../../models/driver_profile.dart';
import 'vehicle_details_step.dart' show RegistrationFormCard;

/// In-memory draft for the single mandatory route collected during
/// registration. Distinct from [RouteDraft] (widgets/route_draft_editor.dart)
/// which also carries direction/active-day scheduling used on the
/// profile's "manage routes" screens — registration only needs the two
/// endpoints, matching the "Select Preferred Route" design.
class RegistrationRouteDraft {
  final TextEditingController originController;
  final TextEditingController destinationController;
  LocationPoint origin;
  LocationPoint destination;
  double? distanceKm;
  int? durationMinutes;

  RegistrationRouteDraft({String origin = '', String destination = ''})
    : origin = LocationPoint(address: origin),
      destination = LocationPoint(address: destination),
      originController = TextEditingController(text: origin),
      destinationController = TextEditingController(text: destination);

  bool get isFilled =>
      originController.text.trim().isNotEmpty &&
      destinationController.text.trim().isNotEmpty;

  RoutePreference toRoutePreference(String driverProfileId) {
    return RoutePreference(
      driverProfileId: driverProfileId,
      origin: origin.copyWith(address: originController.text.trim()),
      destination: destination.copyWith(
        address: destinationController.text.trim(),
      ),
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
    );
  }

  void dispose() {
    originController.dispose();
    destinationController.dispose();
  }
}

/// Step 2 of driver registration — origin/destination pickers, a
/// stylized corridor preview, and the matched distance/duration
/// summary, matching the "Select Preferred Route" design. Mandatory:
/// the parent flow blocks "Complete Registration" until [draft.isFilled].
class RouteSelectionStep extends StatefulWidget {
  final RegistrationRouteDraft draft;
  final VoidCallback onChanged;

  const RouteSelectionStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  @override
  State<RouteSelectionStep> createState() => _RouteSelectionStepState();
}

class _RouteSelectionStepState extends State<RouteSelectionStep> {
  bool _resolving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'route_direction'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'mandatory_step'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RegistrationFormCard(
            children: [
              RouteMapPicker(
                originController: draft.originController,
                destinationController: draft.destinationController,
                initialOrigin: draft.origin,
                initialDestination: draft.destination,
                onOriginChanged: (point) {
                  draft.origin = point;
                  widget.onChanged();
                },
                onDestinationChanged: (point) {
                  draft.destination = point;
                  widget.onChanged();
                },
                onRouteInfo: (distanceKm, durationMinutes) {
                  setState(() {
                    _resolving = false;
                    draft.distanceKm = distanceKm;
                    draft.durationMinutes = durationMinutes;
                  });
                  widget.onChanged();
                },
              ),
            ],
          ),
          if (draft.isFilled) ...[
            const SizedBox(height: 16),
            _SuggestedCorridorCard(draft: draft, resolving: _resolving),
          ],
        ],
      ),
    );
  }
}

class _SuggestedCorridorCard extends StatelessWidget {
  final RegistrationRouteDraft draft;
  final bool resolving;

  const _SuggestedCorridorCard({required this.draft, required this.resolving});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDistance = draft.distanceKm != null;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Text(
                'suggested_corridor'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (resolving)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else if (hasDistance)
                Text(
                  'matched_km'.tr(
                    namedArgs: {'km': draft.distanceKm!.toStringAsFixed(0)},
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.alt_route,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${draft.originController.text.trim()} → ${draft.destinationController.text.trim()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDistance
                            ? 'avg_duration'.tr(
                                namedArgs: {
                                  'duration': _formatDuration(
                                    draft.durationMinutes ?? 0,
                                  ),
                                },
                              )
                            : 'high_ride_demand_route'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
