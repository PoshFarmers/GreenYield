import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../live_tracking_models.dart';
import '../order_providers.dart';

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String viewerRole; // 'buyer', 'farmer'

  const LiveTrackingScreen({
    super.key,
    required this.orderId,
    required this.viewerRole,
  });

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _pollingTimer;

  // Real road route caching
  List<ll.LatLng> _activeRoutePoints = [];
  List<ll.LatLng> _secondaryRoutePoints = [];
  double? _activeRouteDistanceKm;
  int? _activeRouteDurationMin;

  ll.LatLng? _lastRoutedDriverPos;
  ll.LatLng? _lastRoutedTargetPos;
  bool? _lastPickupState;
  bool _isFetchingRoute = false;
  bool _hasInitialCameraFitted = false;

  @override
  void initState() {
    super.initState();
    // Poll every 5 seconds for live GPS updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(liveOrderTrackingProvider(widget.orderId));
    });
    // ref.listen only fires on *changes* — trigger on first load too.
    // Use whenData to safely unwrap the initial async state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveOrderTrackingProvider(widget.orderId)).whenData((tracking) {
        if (tracking != null && mounted) _updateRoadRoutes(tracking);
      });
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Fetches a real road route geometry from OSRM between two coordinates.
  Future<Map<String, dynamic>?> _fetchRoadRoute(
    ll.LatLng start,
    ll.LatLng destination,
  ) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );
      developer.log('OSRM request: $uri', name: 'GreenYield.LiveTracking');
      final response = await http
          .get(uri, headers: {'User-Agent': 'GreenYieldApp/1.0 (lk)'})
          .timeout(const Duration(seconds: 10));
      developer.log(
        'OSRM response: ${response.statusCode} (${response.body.length} bytes)',
        name: 'GreenYield.LiveTracking',
      );
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      if (code != 'Ok') {
        developer.log(
          'OSRM routing failed — code: $code',
          name: 'GreenYield.LiveTracking',
        );
        return null;
      }
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final first = routes.first as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>?;
      if (geometry == null) return null;

      final coords = geometry['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return null;

      final points = <ll.LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          points.add(
            ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          );
        }
      }

      if (points.length < 2) return null;

      final distanceKm = ((first['distance'] as num?)?.toDouble() ?? 0) / 1000;
      final durationMin = (((first['duration'] as num?)?.toDouble() ?? 0) / 60)
          .round();

      developer.log(
        'OSRM route: ${points.length} pts, ${distanceKm.toStringAsFixed(1)} km, $durationMin min',
        name: 'GreenYield.LiveTracking',
      );

      return {
        'points': points,
        'distanceKm': distanceKm,
        'durationMin': durationMin,
      };
    } catch (e, st) {
      developer.log(
        'OSRM fetch error: $e',
        name: 'GreenYield.LiveTracking',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Calculates real road routes when driver location or destination changes significantly.
  void _updateRoadRoutes(LiveOrderTracking tracking) {
    final driver = tracking.driver;
    final farmer = tracking.farmer;
    final buyer = tracking.buyer;
    final isPickedUp = tracking.isPickedUp;

    if (driver == null || !driver.hasCoordinates) {
      return;
    }

    final currentDriverPos = ll.LatLng(driver.latitude!, driver.longitude!);
    final activeTargetPos = isPickedUp
        ? (buyer != null && buyer.hasCoordinates
              ? ll.LatLng(buyer.latitude!, buyer.longitude!)
              : null)
        : (farmer != null && farmer.hasCoordinates
              ? ll.LatLng(farmer.latitude!, farmer.longitude!)
              : null);

    if (activeTargetPos == null) return;

    // Check if we need to recalculate:
    // 1. Pickup status changed
    // 2. Target changed
    // 3. Driver moved more than ~40 meters
    bool shouldRecalculate = false;
    if (_lastPickupState != isPickedUp) {
      shouldRecalculate = true;
    } else if (_lastRoutedTargetPos == null ||
        _distanceBetween(_lastRoutedTargetPos!, activeTargetPos) > 0.05) {
      shouldRecalculate = true;
    } else if (_lastRoutedDriverPos == null ||
        _distanceBetween(_lastRoutedDriverPos!, currentDriverPos) > 0.04) {
      shouldRecalculate = true;
    }

    if (!shouldRecalculate || _isFetchingRoute) return;

    _isFetchingRoute = true;
    _lastPickupState = isPickedUp;
    _lastRoutedDriverPos = currentDriverPos;
    _lastRoutedTargetPos = activeTargetPos;

    Future.microtask(() async {
      final activeRouteData = await _fetchRoadRoute(
        currentDriverPos,
        activeTargetPos,
      );

      List<ll.LatLng>? secondaryPoints;
      // If not yet picked up, also route farmer -> buyer to show full trip context
      if (!isPickedUp &&
          farmer != null &&
          farmer.hasCoordinates &&
          buyer != null &&
          buyer.hasCoordinates) {
        final farmerPos = ll.LatLng(farmer.latitude!, farmer.longitude!);
        final buyerPos = ll.LatLng(buyer.latitude!, buyer.longitude!);
        final secRoute = await _fetchRoadRoute(farmerPos, buyerPos);
        if (secRoute != null) {
          secondaryPoints = secRoute['points'] as List<ll.LatLng>?;
        }
      }

      if (mounted) {
        setState(() {
          _isFetchingRoute = false;
          if (activeRouteData != null) {
            _activeRoutePoints =
                activeRouteData['points'] as List<ll.LatLng>? ?? [];
            _activeRouteDistanceKm = activeRouteData['distanceKm'] as double?;
            _activeRouteDurationMin = activeRouteData['durationMin'] as int?;
          } else {
            // Fallback straight line if OSRM unavailable
            _activeRoutePoints = [currentDriverPos, activeTargetPos];
          }

          if (secondaryPoints != null) {
            _secondaryRoutePoints = secondaryPoints;
          } else if (isPickedUp) {
            _secondaryRoutePoints = [];
          }
        });
      } else {
        _isFetchingRoute = false;
      }
    });
  }

  /// Approximate Euclidean distance in km for threshold comparison
  double _distanceBetween(ll.LatLng a, ll.LatLng b) {
    const ll.Distance distance = ll.Distance();
    return distance.as(ll.LengthUnit.Kilometer, a, b);
  }

  @override
  Widget build(BuildContext context) {
    // Use ref.listen to react to tracking data changes and trigger road
    // route calculation — this is the correct Riverpod pattern for side
    // effects (avoids calling async work from inside build).
    ref.listen<AsyncValue<LiveOrderTracking?>>(
      liveOrderTrackingProvider(widget.orderId),
      (_, next) {
        next.whenData((tracking) {
          if (tracking != null && mounted) {
            _updateRoadRoutes(tracking);
          }
        });
      },
    );

    final trackingAsync = ref.watch(liveOrderTrackingProvider(widget.orderId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const AppSecondaryHeader(
        title: 'Track Order',
        showBackButton: true,
      ),
      body: trackingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Error loading tracking info:\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (tracking) {
          if (tracking == null) {
            return const Center(
              child: Text('Tracking information unavailable.'),
            );
          }

          final driver = tracking.driver;
          final farmer = tracking.farmer;
          final buyer = tracking.buyer;
          final isPickedUp = tracking.isPickedUp;

          final mapPoints = <ll.LatLng>[];
          if (driver != null && driver.hasCoordinates) {
            mapPoints.add(ll.LatLng(driver.latitude!, driver.longitude!));
          }
          if (farmer != null && farmer.hasCoordinates) {
            mapPoints.add(ll.LatLng(farmer.latitude!, farmer.longitude!));
          }
          if (buyer != null && buyer.hasCoordinates) {
            mapPoints.add(ll.LatLng(buyer.latitude!, buyer.longitude!));
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_hasInitialCameraFitted && mapPoints.length >= 2) {
              try {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(mapPoints),
                    padding: const EdgeInsets.all(60),
                  ),
                );
                _hasInitialCameraFitted = true;
              } catch (_) {}
            }
          });

          final defaultCenter = mapPoints.isNotEmpty
              ? mapPoints.first
              : const ll.LatLng(7.8731, 80.7718);

          return Stack(
            children: [
              // Interactive FlutterMap
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: defaultCenter,
                  initialZoom: mapPoints.length > 1 ? 12 : 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.greenyield.app',
                  ),

                  // Real road route polyline layer
                  PolylineLayer(
                    polylines: [
                      // Secondary route (Farmer -> Buyer when still heading to pickup)
                      if (!isPickedUp && _secondaryRoutePoints.isNotEmpty)
                        Polyline(
                          points: _secondaryRoutePoints,
                          strokeWidth: 4,
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.5,
                          ),
                          pattern: const StrokePattern.dotted(),
                        ),

                      // Active driving route (Driver -> Target)
                      if (_activeRoutePoints.isNotEmpty)
                        Polyline(
                          points: _activeRoutePoints,
                          strokeWidth: 5,
                          color: isPickedUp
                              ? Colors.orange.shade700
                              : theme.colorScheme.primary,
                        )
                      else if (mapPoints.length > 1)
                        // Fallback straight line before route loads
                        Polyline(
                          points: mapPoints,
                          strokeWidth: 3,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.4,
                          ),
                          pattern: StrokePattern.dashed(
                            segments: const [10, 8],
                          ),
                        ),
                    ],
                  ),

                  MarkerLayer(
                    markers: [
                      // Farmer Marker
                      if (farmer != null && farmer.hasCoordinates)
                        Marker(
                          point: ll.LatLng(farmer.latitude!, farmer.longitude!),
                          width: 44,
                          height: 44,
                          child: _buildLocationMarker(
                            icon: Icons.storefront,
                            color: Colors.green.shade700,
                            label: 'Farmer',
                          ),
                        ),

                      // Buyer Marker
                      if (buyer != null && buyer.hasCoordinates)
                        Marker(
                          point: ll.LatLng(buyer.latitude!, buyer.longitude!),
                          width: 44,
                          height: 44,
                          child: _buildLocationMarker(
                            icon: Icons.person_pin_circle,
                            color: Colors.blue.shade700,
                            label: 'Buyer',
                          ),
                        ),

                      // Driver Marker (Changes between Vehicle and Package icon after pickup)
                      if (driver != null && driver.hasCoordinates)
                        Marker(
                          point: ll.LatLng(driver.latitude!, driver.longitude!),
                          width: 48,
                          height: 48,
                          child: _buildDriverMarker(
                            isPickedUp: isPickedUp,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // Bottom Info Card Overlay
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status badge & title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPickedUp
                                    ? Colors.orange.shade100
                                    : Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isPickedUp
                                        ? Icons.inventory_2_outlined
                                        : Icons.local_shipping_outlined,
                                    size: 16,
                                    color: isPickedUp
                                        ? Colors.orange.shade900
                                        : Colors.green.shade900,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPickedUp
                                        ? 'Package In Transit'
                                        : 'Heading to Pickup',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isPickedUp
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (driver?.recordedAt != null)
                              Text(
                                'Updated ${_timeAgo(driver!.recordedAt!)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_activeRouteDistanceKm != null &&
                            _activeRouteDurationMin != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alt_route,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_activeRouteDistanceKm!.toStringAsFixed(1)} km road distance',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.timer_outlined,
                                  size: 15,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '~$_activeRouteDurationMin mins away',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Driver Details Row
                        if (driver != null) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.person,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      driver.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Your Delivery Driver',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (driver.phone != null &&
                                  driver.phone!.isNotEmpty)
                                IconButton.filledTonal(
                                  onPressed: () => _makeCall(driver.phone),
                                  icon: const Icon(Icons.call),
                                ),
                            ],
                          ),
                        ] else
                          Text(
                            'Waiting for driver position...',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1),
                        ),

                        // Locations summary
                        Row(
                          children: [
                            if (farmer != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Farmer',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    Text(
                                      farmer.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (farmer != null && buyer != null)
                              const SizedBox(width: 12),
                            if (buyer != null)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Buyer Destination',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    Text(
                                      buyer.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLocationMarker({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6),
        ],
      ),
      child: Center(child: Icon(icon, color: color, size: 26)),
    );
  }

  Widget _buildDriverMarker({required bool isPickedUp, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: isPickedUp ? Colors.orange.shade700 : color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          isPickedUp ? Icons.inventory_2 : Icons.directions_car,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
