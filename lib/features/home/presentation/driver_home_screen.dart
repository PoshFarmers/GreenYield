import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_header.dart';
import '../../../models/driver_stop.dart';
import '../../../models/profile.dart';
import '../../orders/driver_home_providers.dart';
import '../../orders/driver_home_service.dart';
import '../../orders/presentation/order_detail_screen.dart';

/// Driver's Home screen — today's assigned pickups/dropoffs, a
/// "Start Route" action that notifies buyers/farmers, a live map of
/// every stop plus the driver's own position, and a nearest-first
/// list of stops with Navigate / Pickup / Drop-off actions. Each
/// action calls the same `transition_delivery_status` RPC the rest of
/// the app uses, so buyer/farmer order tracking updates automatically
/// (see `transition_order_status`'s notification triggers).
class DriverHomeScreen extends ConsumerStatefulWidget {
  final Profile profile;

  const DriverHomeScreen({super.key, required this.profile});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  static const _service = DriverHomeService();
  final _mapController = MapController();

  ll.LatLng? _myPosition;
  StreamSubscription<Position>? _positionSub;
  bool _startingRoute = false;
  final Set<String> _pendingDeliveryIds = {};

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(
        () => _myPosition = ll.LatLng(position.latitude, position.longitude),
      );

      _positionSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 25,
            ),
          ).listen((pos) {
            if (!mounted) return;
            setState(
              () => _myPosition = ll.LatLng(pos.latitude, pos.longitude),
            );
          });
    } catch (_) {
      // No GPS fix available — the map/list still work, just without
      // "nearest first" sorting or a driver marker.
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  double _distanceMeters(DriverStop stop) {
    if (_myPosition == null || !stop.hasCoordinates) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      _myPosition!.latitude,
      _myPosition!.longitude,
      stop.latitude!,
      stop.longitude!,
    );
  }

  List<DriverStop> _sortedByDistance(List<DriverStop> stops) {
    final pending = stops.where((s) => !s.isDone).toList()
      ..sort((a, b) => _distanceMeters(a).compareTo(_distanceMeters(b)));
    final done = stops.where((s) => s.isDone).toList();
    return [...pending, ...done];
  }

  Future<void> _navigateTo(DriverStop stop) async {
    if (!stop.hasCoordinates) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${stop.latitude},${stop.longitude}&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleStartRoute(List<DriverStop> stops) async {
    final orderIds = stops.map((s) => s.orderId).toSet().toList();
    setState(() => _startingRoute = true);
    try {
      await _service.startShift(orderIds);
      await ref.read(driverShiftStartedProvider.notifier).markStarted();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('route_started_notified'.tr())));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('error_starting_route'.tr(namedArgs: {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) setState(() => _startingRoute = false);
    }
  }

  Future<void> _handleStopAction(DriverStop stop) async {
    setState(() => _pendingDeliveryIds.add(stop.deliveryId));
    try {
      if (stop.type == DriverStopType.pickup) {
        await _service.confirmPickup(stop.deliveryId);
      } else {
        await _service.confirmDropoff(stop.deliveryId);
      }
      ref.invalidate(driverTodayStopsProvider(widget.profile.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (stop.type == DriverStopType.pickup
                    ? 'pickup_confirmed'
                    : 'dropoff_confirmed')
                .tr(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('error_updating_status'.tr(namedArgs: {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingDeliveryIds.remove(stop.deliveryId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopsAsync = ref.watch(driverTodayStopsProvider(widget.profile.id));
    final shiftStarted = ref.watch(driverShiftStartedProvider);

    return Scaffold(
      appBar: AppHeader(profile: widget.profile),
      body: SafeArea(
        child: stopsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'error_loading_deliveries'.tr(namedArgs: {'error': '$e'}),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (rawStops) {
            final stops = _sortedByDistance(rawStops);
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(driverTodayStopsProvider(widget.profile.id));
                await ref.read(
                  driverTodayStopsProvider(widget.profile.id).future,
                );
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final content = isWide
                      ? _WideLayout(
                          stops: stops,
                          myPosition: _myPosition,
                          mapController: _mapController,
                          shiftStarted: shiftStarted,
                          startingRoute: _startingRoute,
                          pendingDeliveryIds: _pendingDeliveryIds,
                          onStartRoute: () => _handleStartRoute(stops),
                          onNavigate: _navigateTo,
                          onStopAction: _handleStopAction,
                          onOpenOrder: (orderId) =>
                              _openOrder(context, orderId),
                        )
                      : _NarrowLayout(
                          stops: stops,
                          myPosition: _myPosition,
                          mapController: _mapController,
                          shiftStarted: shiftStarted,
                          startingRoute: _startingRoute,
                          pendingDeliveryIds: _pendingDeliveryIds,
                          onStartRoute: () => _handleStartRoute(stops),
                          onNavigate: _navigateTo,
                          onStopAction: _handleStopAction,
                          onOpenOrder: (orderId) =>
                              _openOrder(context, orderId),
                        );
                  return content;
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _openOrder(BuildContext context, String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailScreen(orderId: orderId, viewerRole: 'driver'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Responsive layouts
// ---------------------------------------------------------------------------

class _NarrowLayout extends StatelessWidget {
  final List<DriverStop> stops;
  final ll.LatLng? myPosition;
  final MapController mapController;
  final bool shiftStarted;
  final bool startingRoute;
  final Set<String> pendingDeliveryIds;
  final VoidCallback onStartRoute;
  final ValueChanged<DriverStop> onNavigate;
  final ValueChanged<DriverStop> onStopAction;
  final ValueChanged<String> onOpenOrder;

  const _NarrowLayout({
    required this.stops,
    required this.myPosition,
    required this.mapController,
    required this.shiftStarted,
    required this.startingRoute,
    required this.pendingDeliveryIds,
    required this.onStartRoute,
    required this.onNavigate,
    required this.onStopAction,
    required this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _RouteSummaryCard(
          stops: stops,
          shiftStarted: shiftStarted,
          starting: startingRoute,
          onStartRoute: onStartRoute,
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 260,
            child: _StopsMap(
              stops: stops,
              myPosition: myPosition,
              mapController: mapController,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (stops.isEmpty)
          const _EmptyStopsMessage()
        else
          for (final stop in stops) ...[
            _StopCard(
              stop: stop,
              isNearest:
                  !stop.isDone &&
                  stops.firstWhere((s) => !s.isDone, orElse: () => stop) ==
                      stop,
              isPending: pendingDeliveryIds.contains(stop.deliveryId),
              onNavigate: () => onNavigate(stop),
              onAction: () => onStopAction(stop),
              onTap: () => onOpenOrder(stop.orderId),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _WideLayout extends StatelessWidget {
  final List<DriverStop> stops;
  final ll.LatLng? myPosition;
  final MapController mapController;
  final bool shiftStarted;
  final bool startingRoute;
  final Set<String> pendingDeliveryIds;
  final VoidCallback onStartRoute;
  final ValueChanged<DriverStop> onNavigate;
  final ValueChanged<DriverStop> onStopAction;
  final ValueChanged<String> onOpenOrder;

  const _WideLayout({
    required this.stops,
    required this.myPosition,
    required this.mapController,
    required this.shiftStarted,
    required this.startingRoute,
    required this.pendingDeliveryIds,
    required this.onStartRoute,
    required this.onNavigate,
    required this.onStopAction,
    required this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RouteSummaryCard(
                  stops: stops,
                  shiftStarted: shiftStarted,
                  starting: startingRoute,
                  onStartRoute: onStartRoute,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _StopsMap(
                      stops: stops,
                      myPosition: myPosition,
                      mapController: mapController,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: stops.isEmpty
                ? const _EmptyStopsMessage()
                : ListView(
                    children: [
                      for (final stop in stops) ...[
                        _StopCard(
                          stop: stop,
                          isNearest:
                              !stop.isDone &&
                              stops.firstWhere(
                                    (s) => !s.isDone,
                                    orElse: () => stop,
                                  ) ==
                                  stop,
                          isPending: pendingDeliveryIds.contains(
                            stop.deliveryId,
                          ),
                          onNavigate: () => onNavigate(stop),
                          onAction: () => onStopAction(stop),
                          onTap: () => onOpenOrder(stop.orderId),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route summary + Start button
// ---------------------------------------------------------------------------

class _RouteSummaryCard extends StatelessWidget {
  final List<DriverStop> stops;
  final bool shiftStarted;
  final bool starting;
  final VoidCallback onStartRoute;

  const _RouteSummaryCard({
    required this.stops,
    required this.shiftStarted,
    required this.starting,
    required this.onStartRoute,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = stops.where((s) => s.isDone).length;
    final pending = stops.length - completed;
    final progress = stops.isEmpty ? 0.0 : completed / stops.length;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'todays_route'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.yMMMd(context.locale.toString()).format(today),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'n_stops'.tr(namedArgs: {'count': '${stops.length}'}),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: theme.colorScheme.onPrimary.withValues(
                alpha: 0.25,
              ),
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.onPrimary),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'n_completed'.tr(namedArgs: {'count': '$completed'}),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
              Text(
                'n_pending'.tr(namedArgs: {'count': '$pending'}),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: shiftStarted
                ? FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('route_in_progress'.tr()),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.onPrimary.withValues(
                        alpha: 0.18,
                      ),
                      disabledBackgroundColor: theme.colorScheme.onPrimary
                          .withValues(alpha: 0.18),
                      foregroundColor: theme.colorScheme.onPrimary,
                      disabledForegroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: (starting || stops.isEmpty)
                        ? null
                        : onStartRoute,
                    icon: starting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text('start_route'.tr()),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.onPrimary,
                      foregroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

class _StopsMap extends StatelessWidget {
  final List<DriverStop> stops;
  final ll.LatLng? myPosition;
  final MapController mapController;

  const _StopsMap({
    required this.stops,
    required this.myPosition,
    required this.mapController,
  });

  static const _srilankaCenter = ll.LatLng(7.8731, 80.7718);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = <ll.LatLng>[
      if (myPosition != null) myPosition!,
      for (final s in stops)
        if (s.hasCoordinates) ll.LatLng(s.latitude!, s.longitude!),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (points.length < 2) return;
      try {
        mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    });

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: points.isNotEmpty ? points.first : _srilankaCenter,
        initialZoom: points.isNotEmpty ? 12 : 7,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.greenyield.app',
        ),
        if (points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (myPosition != null)
              Marker(
                point: myPosition!,
                width: 34,
                height: 34,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.secondary,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            for (final stop in stops)
              if (stop.hasCoordinates)
                Marker(
                  point: ll.LatLng(stop.latitude!, stop.longitude!),
                  width: 40,
                  height: 40,
                  child: Icon(
                    stop.type == DriverStopType.pickup
                        ? Icons.storefront
                        : Icons.location_on,
                    size: 34,
                    color: stop.isDone
                        ? theme.colorScheme.outline
                        : stop.type == DriverStopType.pickup
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stop list card
// ---------------------------------------------------------------------------

class _StopCard extends StatelessWidget {
  final DriverStop stop;
  final bool isNearest;
  final bool isPending;
  final VoidCallback onNavigate;
  final VoidCallback onAction;
  final VoidCallback onTap;

  const _StopCard({
    required this.stop,
    required this.isNearest,
    required this.isPending,
    required this.onNavigate,
    required this.onAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPickup = stop.type == DriverStopType.pickup;

    final Color accent = stop.isDone
        ? theme.colorScheme.outline
        : isPickup
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isNearest ? accent : theme.colorScheme.outlineVariant,
            width: isNearest ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(
                  label: stop.isDone
                      ? (isPickup
                            ? 'status_picked_up'.tr()
                            : 'status_delivered'.tr())
                      : isNearest
                      ? (isPickup
                            ? 'status_pending_pickup_nearest'.tr()
                            : 'status_pending_dropoff_nearest'.tr())
                      : (isPickup
                            ? 'status_pending_pickup'.tr()
                            : 'status_pending_dropoff'.tr()),
                  color: accent,
                  done: stop.isDone,
                ),
                const Spacer(),
                Text(
                  stop.displayOrderId,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isPickup ? Icons.storefront : Icons.location_on,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (isPickup ? 'pickup_colon'.tr() : 'dropoff_colon'.tr()) +
                        (stop.counterpartName ?? '—'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (stop.cropNames != null && stop.cropNames!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  stop.cropNames!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (stop.address != null && stop.address!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    stop.address!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: stop.hasCoordinates ? onNavigate : null,
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: Text('navigate'.tr()),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (!stop.isDone) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isPending ? null : onAction,
                      icon: isPending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        isPickup ? 'picked_up'.tr() : 'delivered'.tr(),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool done;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.schedule,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStopsMessage extends StatelessWidget {
  const _EmptyStopsMessage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 52,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'no_stops_today'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
