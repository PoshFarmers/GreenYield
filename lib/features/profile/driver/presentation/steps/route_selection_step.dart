import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

import '../../../../../core/widgets/app_text_field.dart';
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
  Timer? _debounce;
  bool _resolving = false;
  final _geocoding = geocoding.Geocoding();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Debounced geocode of both endpoints, so we're not hitting the
  /// geocoding backend on every keystroke. Best-effort only — a typed
  /// address that fails to resolve is still saved as free text (see
  /// [LocationPoint]).
  void _scheduleResolve() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _resolveEndpoints);
  }

  Future<void> _resolveEndpoints() async {
    final draft = widget.draft;
    if (!draft.isFilled) return;
    setState(() => _resolving = true);
    try {
      final originResult = await _geocode(draft.originController.text.trim());
      final destResult = await _geocode(
        draft.destinationController.text.trim(),
      );
      draft.origin = draft.origin.copyWith(
        address: draft.originController.text.trim(),
        latitude: originResult?.latitude,
        longitude: originResult?.longitude,
      );
      draft.destination = draft.destination.copyWith(
        address: draft.destinationController.text.trim(),
        latitude: destResult?.latitude,
        longitude: destResult?.longitude,
      );
      if (draft.origin.hasCoordinates && draft.destination.hasCoordinates) {
        final km = _haversineKm(
          draft.origin.latitude!,
          draft.origin.longitude!,
          draft.destination.latitude!,
          draft.destination.longitude!,
        );
        draft.distanceKm = km;
        // Rough average-speed estimate for an inter-town corridor;
        // this is a placeholder until a routing API is wired in.
        draft.durationMinutes = (km / 55 * 60).round();
      }
    } catch (_) {
      // Geocoding is best-effort (network/permission errors, no
      // matches, etc.) — the free-text address is still valid.
    } finally {
      if (mounted) setState(() => _resolving = false);
      widget.onChanged();
    }
  }

  Future<geocoding.Location?> _geocode(String address) async {
    if (address.isEmpty) return null;
    // geocoding 5.x wraps everything in a `Geocoding` instance rather
    // than exposing top-level functions.
    final results = await _geocoding.locationFromAddress(address);
    return results.isEmpty ? null : results.first;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);

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
              _EndpointField(
                icon: Icons.trip_origin,
                iconColor: theme.colorScheme.primary,
                label: 'start_location'.tr(),
                controller: draft.originController,
                onChanged: (_) {
                  widget.onChanged();
                  _scheduleResolve();
                },
                onClear: () => setState(() {
                  draft.originController.clear();
                  draft.origin = LocationPoint.empty;
                  widget.onChanged();
                }),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 9),
                    SizedBox(
                      height: 18,
                      child: VerticalDivider(
                        width: 18,
                        thickness: 1.4,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _EndpointField(
                icon: Icons.location_on,
                iconColor: theme.colorScheme.tertiary,
                label: 'end_location'.tr(),
                controller: draft.destinationController,
                onChanged: (_) {
                  widget.onChanged();
                  _scheduleResolve();
                },
                onClear: () => setState(() {
                  draft.destinationController.clear();
                  draft.destination = LocationPoint.empty;
                  widget.onChanged();
                }),
              ),
            ],
          ),
          if (draft.isFilled) ...[
            const SizedBox(height: 16),
            _SuggestedCorridorCard(draft: draft, resolving: _resolving),
            const SizedBox(height: 16),
            _RoutePreviewMap(draft: draft),
            const SizedBox(height: 12),
            _DistanceSummaryBar(draft: draft),
          ],
        ],
      ),
    );
  }
}

class _EndpointField extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _EndpointField({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onClear,
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
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox(width: 40)
              : IconButton(
                  icon: const Icon(Icons.cancel, size: 18),
                  tooltip: 'clear'.tr(),
                  onPressed: onClear,
                ),
        ),
      ],
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

/// Stylized, theme-aware route preview: a dashed corridor line over a
/// light grid, echoing the map in the design without depending on a
/// maps SDK/API key. Swap this out for a real GoogleMap/MapLibre widget
/// once map tiles are wired up — [RegistrationRouteDraft] already
/// carries the resolved lat/lng needed to drive one.
class _RoutePreviewMap extends StatelessWidget {
  final RegistrationRouteDraft draft;

  const _RoutePreviewMap({required this.draft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 11,
        child: Container(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          child: CustomPaint(
            painter: _RoutePreviewPainter(
              gridColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              lineColor: theme.colorScheme.primary,
              startColor: theme.colorScheme.primary,
              endColor: theme.colorScheme.error,
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    draft.origin.address.isEmpty
                        ? ''
                        : 'start_prefix'.tr(
                            namedArgs: {'place': draft.origin.address},
                          ),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  final Color gridColor;
  final Color lineColor;
  final Color startColor;
  final Color endColor;

  _RoutePreviewPainter({
    required this.gridColor,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += size.height / 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final start = Offset(size.width * 0.22, size.height * 0.82);
    final end = Offset(size.width * 0.72, size.height * 0.14);
    final control = Offset(size.width * 0.62, size.height * 0.78);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    final dashed = _dashPath(path, dashLength: 8, gapLength: 6);
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(dashed, linePaint);

    _drawMarker(canvas, start, startColor);
    _drawMarker(canvas, end, endColor);
  }

  void _drawMarker(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 9, Paint()..color = Colors.white);
    canvas.drawCircle(center, 7, Paint()..color = color);
  }

  Path _dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        final next = math.min(distance + length, metric.length);
        if (draw) {
          dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        distance = next;
        draw = !draw;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) => false;
}

class _DistanceSummaryBar extends StatelessWidget {
  final RegistrationRouteDraft draft;

  const _DistanceSummaryBar({required this.draft});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (draft.distanceKm == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.navigation, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'distance_duration_summary'.tr(
                namedArgs: {
                  'km': draft.distanceKm!.toStringAsFixed(1),
                  'duration': _formatDuration(draft.durationMinutes ?? 0),
                },
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'optimal'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
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
