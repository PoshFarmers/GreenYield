import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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
  bool _isFullscreen = false;
  DriverStop? _navigatingStop;

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
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted && _myPosition == null) {
        setState(
          () =>
              _myPosition = ll.LatLng(lastKnown.latitude, lastKnown.longitude),
        );
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
    setState(() => _navigatingStop = stop);
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
      appBar: _isFullscreen ? null : AppHeader(profile: widget.profile),
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

            if (_isFullscreen) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) {
                    setState(() => _isFullscreen = false);
                  }
                },
                child: SizedBox.expand(
                  child: _StopsMap(
                    stops: stops,
                    myPosition: _myPosition,
                    mapController: _mapController,
                    navigatingStop: _navigatingStop,
                    isFullscreen: true,
                    onToggleFullscreen: () {
                      setState(() => _isFullscreen = false);
                    },
                    onClearNavigation: () {
                      setState(() => _navigatingStop = null);
                    },
                  ),
                ),
              );
            }

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
                          navigatingStop: _navigatingStop,
                          onToggleFullscreen: () {
                            setState(() => _isFullscreen = true);
                          },
                          onClearNavigation: () {
                            setState(() => _navigatingStop = null);
                          },
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
                          navigatingStop: _navigatingStop,
                          onToggleFullscreen: () {
                            setState(() => _isFullscreen = true);
                          },
                          onClearNavigation: () {
                            setState(() => _navigatingStop = null);
                          },
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
  final DriverStop? navigatingStop;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClearNavigation;
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
    required this.navigatingStop,
    required this.onToggleFullscreen,
    required this.onClearNavigation,
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
            height: 280,
            child: _StopsMap(
              stops: stops,
              myPosition: myPosition,
              mapController: mapController,
              navigatingStop: navigatingStop,
              isFullscreen: false,
              onToggleFullscreen: onToggleFullscreen,
              onClearNavigation: onClearNavigation,
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
  final DriverStop? navigatingStop;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClearNavigation;
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
    required this.navigatingStop,
    required this.onToggleFullscreen,
    required this.onClearNavigation,
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
                      navigatingStop: navigatingStop,
                      isFullscreen: false,
                      onToggleFullscreen: onToggleFullscreen,
                      onClearNavigation: onClearNavigation,
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
// Map — real road routing via OSRM with color-coded segments
// ---------------------------------------------------------------------------

class _StopsMap extends StatefulWidget {
  final List<DriverStop> stops;
  final ll.LatLng? myPosition;
  final MapController mapController;
  final DriverStop? navigatingStop;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClearNavigation;

  const _StopsMap({
    required this.stops,
    required this.myPosition,
    required this.mapController,
    this.navigatingStop,
    this.isFullscreen = false,
    required this.onToggleFullscreen,
    required this.onClearNavigation,
  });

  @override
  State<_StopsMap> createState() => _StopsMapState();
}

class _StopsMapState extends State<_StopsMap>
    with SingleTickerProviderStateMixin {
  static const _srilankaCenter = ll.LatLng(7.8731, 80.7718);

  // Each segment: {points, color, isRoad}
  final List<Map<String, dynamic>> _routeSegments = [];
  List<ll.LatLng>? _navigatingRoutePoints;
  bool _isFetchingRoutes = false;
  bool _hasInitialFit = false;

  // Pulsing animation for driver marker
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fetchAllRoutes();
  }

  @override
  void didUpdateWidget(_StopsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-route when driver moves significantly (> 30 m), stops change, or active navigating stop changes
    final posChanged =
        widget.myPosition != oldWidget.myPosition &&
        widget.myPosition != null &&
        oldWidget.myPosition != null &&
        _distKm(widget.myPosition!, oldWidget.myPosition!) > 0.03;
    final stopsChanged = widget.stops.length != oldWidget.stops.length;
    final navChanged =
        widget.navigatingStop?.deliveryId !=
            oldWidget.navigatingStop?.deliveryId ||
        widget.navigatingStop?.type != oldWidget.navigatingStop?.type;
    if ((posChanged || stopsChanged || navChanged) && !_isFetchingRoutes) {
      _fetchAllRoutes();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  double _distKm(ll.LatLng a, ll.LatLng b) {
    const ll.Distance d = ll.Distance();
    return d.as(ll.LengthUnit.Kilometer, a, b);
  }

  /// Fetch a single road route segment from OSRM.
  Future<List<ll.LatLng>?> _osrmRoute(ll.LatLng start, ll.LatLng end) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http
          .get(uri, headers: {'User-Agent': 'GreenYieldApp/1.0 (lk)'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if ((data['code'] as String?) != 'Ok') return null;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final first = routes.first as Map<String, dynamic>;
      final coords =
          ((first['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List?) ??
          [];
      final pts = <ll.LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          pts.add(
            ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          );
        }
      }
      return pts.length >= 2 ? pts : null;
    } catch (e) {
      developer.log('OSRM error: $e', name: 'GreenYield.DriverMap');
      return null;
    }
  }

  Future<void> _fetchAllRoutes() async {
    if (_isFetchingRoutes) return;
    _isFetchingRoutes = true;

    // Check if we need to fetch the active navigation route in blue
    List<ll.LatLng>? activeNavPoints;
    if (widget.navigatingStop != null &&
        widget.navigatingStop!.hasCoordinates &&
        widget.myPosition != null) {
      final navTarget = ll.LatLng(
        widget.navigatingStop!.latitude!,
        widget.navigatingStop!.longitude!,
      );
      final pts = await _osrmRoute(widget.myPosition!, navTarget);
      activeNavPoints = pts ?? [widget.myPosition!, navTarget];
    }

    // Build ordered waypoints for overall route: driver → pending stops
    final waypoints = <({ll.LatLng pos, Color color, String label})>[];
    if (widget.myPosition != null) {
      waypoints.add((
        pos: widget.myPosition!,
        color: Colors.transparent,
        label: 'me',
      ));
    }
    for (final stop in widget.stops.where(
      (s) => !s.isDone && s.hasCoordinates,
    )) {
      waypoints.add((
        pos: ll.LatLng(stop.latitude!, stop.longitude!),
        color: stop.type == DriverStopType.pickup
            ? const Color(0xFF2E7D32) // Green for pickup
            : const Color(0xFFE65100), // Orange for dropoff
        label: stop.type == DriverStopType.pickup ? 'pickup' : 'dropoff',
      ));
    }

    final segments = <Map<String, dynamic>>[];
    if (waypoints.length >= 2) {
      for (int i = 0; i < waypoints.length - 1; i++) {
        final from = waypoints[i].pos;
        final toWp = waypoints[i + 1];
        final roadPts = await _osrmRoute(from, toWp.pos);
        segments.add({
          'points': roadPts ?? [from, toWp.pos],
          'color': toWp.color,
          'isRoad': roadPts != null,
        });
      }
    }

    if (mounted) {
      setState(() {
        _navigatingRoutePoints = activeNavPoints;
        _routeSegments
          ..clear()
          ..addAll(segments);
        _isFetchingRoutes = false;
      });
    } else {
      _isFetchingRoutes = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final allPoints = <ll.LatLng>[
      if (widget.myPosition != null) widget.myPosition!,
      for (final s in widget.stops)
        if (s.hasCoordinates) ll.LatLng(s.latitude!, s.longitude!),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialFit && allPoints.length >= 2) {
        try {
          widget.mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(allPoints),
              padding: const EdgeInsets.all(52),
            ),
          );
          _hasInitialFit = true;
        } catch (_) {}
      }
    });

    return Stack(
      children: [
        FlutterMap(
          mapController: widget.mapController,
          options: MapOptions(
            initialCenter: allPoints.isNotEmpty
                ? allPoints.first
                : _srilankaCenter,
            initialZoom: allPoints.isNotEmpty ? 12 : 7,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.greenyield.app',
            ),

            // Base road route segments — green (pickups) & orange (dropoffs)
            if (_routeSegments.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final seg in _routeSegments)
                    Polyline(
                      points: seg['points'] as List<ll.LatLng>,
                      strokeWidth: 4.5,
                      color: (seg['color'] as Color).withValues(
                        alpha: widget.navigatingStop != null ? 0.35 : 0.85,
                      ),
                      pattern: (seg['isRoad'] as bool)
                          ? const StrokePattern.solid()
                          : StrokePattern.dashed(segments: const [10, 6]),
                    ),
                ],
              )
            else if (allPoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: allPoints,
                    strokeWidth: 3,
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    pattern: StrokePattern.dashed(segments: const [8, 6]),
                  ),
                ],
              ),

            // Active Navigation Route — vivid blue
            if (_navigatingRoutePoints != null &&
                _navigatingRoutePoints!.isNotEmpty)
              PolylineLayer(
                polylines: [
                  // Outer halo for high contrast visibility
                  Polyline(
                    points: _navigatingRoutePoints!,
                    strokeWidth: 9,
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.3),
                  ),
                  // Main blue road line
                  Polyline(
                    points: _navigatingRoutePoints!,
                    strokeWidth: 5.5,
                    color: const Color(0xFF1976D2),
                  ),
                ],
              ),

            MarkerLayer(
              markers: [
                // Driver marker — prominent real-time location with truck icon & pulsing badge
                if (widget.myPosition != null)
                  Marker(
                    point: widget.myPosition!,
                    width: 60,
                    height: 60,
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, _) => Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring
                          Container(
                            width: 52 * _pulseAnim.value,
                            height: 52 * _pulseAnim.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1976D2)
                                  .withValues(alpha: 0.28 / _pulseAnim.value),
                            ),
                          ),
                          // Truck badge
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.local_shipping,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Stop markers (highlighting active navigation target)
                for (final stop in widget.stops)
                  if (stop.hasCoordinates)
                    Marker(
                      point: ll.LatLng(stop.latitude!, stop.longitude!),
                      width: 50,
                      height: 62,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(
                            builder: (context) {
                              final isNavTarget =
                                  widget.navigatingStop != null &&
                                  widget.navigatingStop!.deliveryId ==
                                      stop.deliveryId &&
                                  widget.navigatingStop!.type == stop.type;
                              return Container(
                                width: isNavTarget ? 42 : 36,
                                height: isNavTarget ? 42 : 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: stop.isDone
                                      ? theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                      : isNavTarget
                                      ? const Color(0xFF1976D2)
                                      : stop.type == DriverStopType.pickup
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE65100),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: isNavTarget ? 3 : 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.28,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  stop.isDone
                                      ? Icons.check
                                      : isNavTarget
                                      ? Icons.navigation
                                      : stop.type == DriverStopType.pickup
                                      ? Icons.storefront
                                      : Icons.home_work,
                                  size: isNavTarget ? 22 : 18,
                                  color: Colors.white,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (context) {
                              final isNavTarget =
                                  widget.navigatingStop != null &&
                                  widget.navigatingStop!.deliveryId ==
                                      stop.deliveryId &&
                                  widget.navigatingStop!.type == stop.type;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isNavTarget
                                      ? const Color(0xFF1976D2)
                                      : Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  stop.type == DriverStopType.pickup
                                      ? 'Pickup'
                                      : 'Drop',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ],
        ),

        // Fullscreen Toggle Button (<> icon overlay)
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: Colors.white.withValues(alpha: 0.95),
            elevation: 4,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.onToggleFullscreen,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  size: 24,
                  color: const Color(0xFF2E7D32),
                ),
              ),
            ),
          ),
        ),

        // Center on driver button
        if (widget.myPosition != null)
          Positioned(
            top: 60,
            right: 12,
            child: Material(
              color: Colors.white.withValues(alpha: 0.95),
              elevation: 4,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  widget.mapController.move(widget.myPosition!, 15);
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.my_location,
                    size: 22,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ),
            ),
          ),

        // Active Navigation Banner Overlay
        if (widget.navigatingStop != null)
          Positioned(
            top: 12,
            left: 12,
            right: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.navigation, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Navigating to ${widget.navigatingStop!.counterpartName ?? widget.navigatingStop!.displayOrderId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: widget.onClearNavigation,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Routing in progress spinner overlay
        if (_isFetchingRoutes)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Routing...',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
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
