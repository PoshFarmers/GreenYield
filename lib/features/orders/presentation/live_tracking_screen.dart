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

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  Timer? _pollingTimer;

  // Real road route caching
  List<ll.LatLng> _activeRoutePoints = [];
  double? _activeRouteDistanceKm;
  int? _activeRouteDurationMin;

  ll.LatLng? _lastRoutedStartPos;
  ll.LatLng? _lastRoutedTargetPos;
  bool? _lastPickupState;
  bool _isFetchingRoute = false;
  bool _hasInitialCameraFitted = false;

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

    // Poll every 5 seconds for live GPS updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(liveOrderTrackingProvider(widget.orderId));
    });
    // Trigger on first load safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(liveOrderTrackingProvider(widget.orderId)).whenData((tracking) {
        if (tracking != null && mounted) _updateRoadRoutes(tracking);
      });
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
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
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code'] as String?;
      if (code != 'Ok') return null;

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

      return {
        'points': points,
        'distanceKm': distanceKm,
        'durationMin': durationMin,
      };
    } catch (e) {
      developer.log('OSRM fetch error: $e', name: 'GreenYield.LiveTracking');
      return null;
    }
  }

  /// Calculates real road routes:
  /// Before pickup: farmer location -> buyer location
  /// After pickup: driver real-time GPS location -> buyer location
  void _updateRoadRoutes(LiveOrderTracking tracking) {
    final driver = tracking.driver;
    final farmer = tracking.farmer;
    final buyer = tracking.buyer;
    final isPickedUp = tracking.isPickedUp;

    ll.LatLng? startPos;
    ll.LatLng? destPos;

    if (buyer != null && buyer.hasCoordinates) {
      destPos = ll.LatLng(buyer.latitude!, buyer.longitude!);
    }

    if (isPickedUp) {
      // Package picked up: route is from driver's real-time GPS to buyer
      if (driver != null && driver.hasCoordinates) {
        startPos = ll.LatLng(driver.latitude!, driver.longitude!);
      } else if (farmer != null && farmer.hasCoordinates) {
        startPos = ll.LatLng(farmer.latitude!, farmer.longitude!);
      }
    } else {
      // Till package picked up: route represents Farmer -> Buyer delivery journey
      if (farmer != null && farmer.hasCoordinates) {
        startPos = ll.LatLng(farmer.latitude!, farmer.longitude!);
      }
    }

    if (startPos == null || destPos == null) return;

    bool shouldRecalculate = false;
    if (_lastPickupState != isPickedUp) {
      shouldRecalculate = true;
    } else if (_lastRoutedStartPos == null ||
        _distanceBetween(_lastRoutedStartPos!, startPos) > 0.04) {
      shouldRecalculate = true;
    } else if (_lastRoutedTargetPos == null ||
        _distanceBetween(_lastRoutedTargetPos!, destPos) > 0.05) {
      shouldRecalculate = true;
    }

    if (!shouldRecalculate || _isFetchingRoute) return;

    _isFetchingRoute = true;
    _lastPickupState = isPickedUp;
    _lastRoutedStartPos = startPos;
    _lastRoutedTargetPos = destPos;

    Future.microtask(() async {
      final routeData = await _fetchRoadRoute(startPos!, destPos!);

      if (mounted) {
        setState(() {
          _isFetchingRoute = false;
          if (routeData != null) {
            _activeRoutePoints = routeData['points'] as List<ll.LatLng>? ?? [];
            _activeRouteDistanceKm = routeData['distanceKm'] as double?;
            _activeRouteDurationMin = routeData['durationMin'] as int?;
          } else {
            // Fallback straight line only if OSRM service is temporarily down
            _activeRoutePoints = [startPos!, destPos!];
          }
        });
      } else {
        _isFetchingRoute = false;
      }
    });
  }

  /// Approximate distance in km for threshold comparison
  double _distanceBetween(ll.LatLng a, ll.LatLng b) {
    const ll.Distance distance = ll.Distance();
    return distance.as(ll.LengthUnit.Kilometer, a, b);
  }

  @override
  Widget build(BuildContext context) {
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
        skipLoadingOnReload: true,
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
          // Before pickup: show Farmer and Buyer (till package picked up, view farmer location)
          // After pickup: show Driver real-time location and Buyer
          if (!isPickedUp) {
            if (farmer != null && farmer.hasCoordinates) {
              mapPoints.add(ll.LatLng(farmer.latitude!, farmer.longitude!));
            }
          } else {
            if (driver != null && driver.hasCoordinates) {
              mapPoints.add(ll.LatLng(driver.latitude!, driver.longitude!));
            } else if (farmer != null && farmer.hasCoordinates) {
              mapPoints.add(ll.LatLng(farmer.latitude!, farmer.longitude!));
            }
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
                      if (_activeRoutePoints.isNotEmpty) ...[
                        // Outer subtle glow/halo for road visibility
                        Polyline(
                          points: _activeRoutePoints,
                          strokeWidth: 9,
                          color:
                              (isPickedUp
                                      ? const Color(0xFF1976D2)
                                      : const Color(0xFF2E7D32))
                                  .withValues(alpha: 0.25),
                        ),
                        // Real road route line
                        Polyline(
                          points: _activeRoutePoints,
                          strokeWidth: 5.5,
                          color: isPickedUp
                              ? const Color(0xFF1976D2) // Blue during transit
                              : const Color(0xFF2E7D32), // Green pre-pickup
                        ),
                      ],
                    ],
                  ),

                  MarkerLayer(
                    markers: [
                      // Farmer Marker: visible before pickup
                      if (!isPickedUp &&
                          farmer != null &&
                          farmer.hasCoordinates)
                        Marker(
                          point: ll.LatLng(farmer.latitude!, farmer.longitude!),
                          width: 48,
                          height: 48,
                          child: _buildLocationMarker(
                            icon: Icons.storefront,
                            color: const Color(0xFF2E7D32),
                            label: 'Farmer',
                          ),
                        ),

                      // Driver Marker: visible after package picked up (with animated pulsing truck icon)
                      if (isPickedUp && driver != null && driver.hasCoordinates)
                        Marker(
                          point: ll.LatLng(driver.latitude!, driver.longitude!),
                          width: 60,
                          height: 60,
                          child: _buildDriverMarker(),
                        ),

                      // Destination Buyer Marker
                      if (buyer != null && buyer.hasCoordinates)
                        Marker(
                          point: ll.LatLng(buyer.latitude!, buyer.longitude!),
                          width: 48,
                          height: 48,
                          child: _buildLocationMarker(
                            icon: Icons.person_pin_circle,
                            color: const Color(0xFFE65100),
                            label: 'Buyer',
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // Route Loading Banner Overlay
              if (_isFetchingRoute)
                Positioned(
                  top: 16,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Loading real road route data...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                    ? const Color(0xFFE3F2FD)
                                    : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isPickedUp
                                        ? Icons.local_shipping
                                        : Icons.storefront,
                                    size: 16,
                                    color: isPickedUp
                                        ? const Color(0xFF1976D2)
                                        : const Color(0xFF2E7D32),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPickedUp
                                        ? 'Package In Transit'
                                        : 'Awaiting Pickup from Farmer',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isPickedUp
                                          ? const Color(0xFF1976D2)
                                          : const Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (isPickedUp && driver?.recordedAt != null)
                              Text(
                                'Updated ${_timeAgo(driver!.recordedAt!)}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Route Distance & Time calculation
                        if (_activeRouteDistanceKm != null &&
                            _activeRouteDurationMin != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alt_route,
                                  size: 16,
                                  color: isPickedUp
                                      ? const Color(0xFF1976D2)
                                      : const Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_activeRouteDistanceKm!.toStringAsFixed(1)} km street route',
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
                                  color: isPickedUp
                                      ? const Color(0xFF1976D2)
                                      : const Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '~$_activeRouteDurationMin mins',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isPickedUp
                                        ? const Color(0xFF1976D2)
                                        : const Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Current tracked party details
                        if (isPickedUp) ...[
                          // Driver In-Transit details
                          if (driver != null)
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF1976D2)
                                      .withValues(alpha: 0.15),
                                  child: const Icon(
                                    Icons.local_shipping,
                                    color: Color(0xFF1976D2),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        driver.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Delivery Driver (Real-time GPS)',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
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
                            )
                          else
                            Text(
                              'Waiting for driver GPS signal...',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ] else ...[
                          // Farmer pickup details
                          if (farmer != null)
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF2E7D32)
                                      .withValues(alpha: 0.15),
                                  child: const Icon(
                                    Icons.storefront,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        farmer.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Farmer / Pickup Location',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (farmer.phone != null &&
                                    farmer.phone!.isNotEmpty)
                                  IconButton.filledTonal(
                                    onPressed: () => _makeCall(farmer.phone),
                                    icon: const Icon(Icons.call),
                                  ),
                              ],
                            )
                          else
                            Text(
                              'Awaiting farmer pickup information...',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1),
                        ),

                        // Destination summary
                        if (buyer != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Color(0xFFE65100),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  buyer.address != null &&
                                          buyer.address!.isNotEmpty
                                      ? buyer.address!
                                      : 'Deliver to ${buyer.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: Icon(icon, color: color, size: 24)),
    );
  }

  Widget _buildDriverMarker() {
    return AnimatedBuilder(
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
              border: Border.all(color: Colors.white, width: 2.5),
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
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
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
