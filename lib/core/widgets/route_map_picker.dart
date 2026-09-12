import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../../models/driver_profile.dart' show LocationPoint;

enum RouteMapEndpoint { origin, destination }

/// Real-map origin/destination picker for a preferred route, shared by
/// the profile "Preferred Routes" editor and the registration route
/// step. Shows actual OpenStreetMap tiles centered on Sri Lanka, with
/// start/end markers placed by search or map tap, and the real
/// road-network path between them (via OSRM's public routing API)
/// instead of a straight line or stylized preview.
class RouteMapPicker extends StatefulWidget {
  final TextEditingController originController;
  final TextEditingController destinationController;
  final LocationPoint initialOrigin;
  final LocationPoint initialDestination;
  final ValueChanged<LocationPoint> onOriginChanged;
  final ValueChanged<LocationPoint> onDestinationChanged;

  /// Called whenever a real route is (re)computed, with the actual
  /// road distance/duration from OSRM — `null` values mean routing
  /// failed and the caller should fall back to its own estimate.
  final void Function(double? distanceKm, int? durationMinutes)? onRouteInfo;

  const RouteMapPicker({
    super.key,
    required this.originController,
    required this.destinationController,
    this.initialOrigin = LocationPoint.empty,
    this.initialDestination = LocationPoint.empty,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    this.onRouteInfo,
  });

  @override
  State<RouteMapPicker> createState() => _RouteMapPickerState();
}

class _RouteMapPickerState extends State<RouteMapPicker> {
  // Sri Lanka's rough bounding box — centers the map and bounds
  // Nominatim search results so a place name resolves to the local
  // town rather than a namesake elsewhere in the world.
  static const _srilankaCenter = ll.LatLng(7.8731, 80.7718);
  static const _minLon = 79.4, _minLat = 5.6, _maxLon = 82.2, _maxLat = 10.2;

  final _mapController = MapController();
  ll.LatLng? _origin;
  ll.LatLng? _destination;
  List<ll.LatLng> _routePoints = [];
  RouteMapEndpoint _active = RouteMapEndpoint.origin;
  bool _searchingOrigin = false;
  bool _searchingDestination = false;
  bool _routing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrigin.hasCoordinates) {
      _origin = ll.LatLng(
        widget.initialOrigin.latitude!,
        widget.initialOrigin.longitude!,
      );
    }
    if (widget.initialDestination.hasCoordinates) {
      _destination = ll.LatLng(
        widget.initialDestination.latitude!,
        widget.initialDestination.longitude!,
      );
    }
    _active = _origin == null
        ? RouteMapEndpoint.origin
        : RouteMapEndpoint.destination;
    if (_origin != null && _destination != null) {
      _fetchRoute();
    }
  }

  @override
  void didUpdateWidget(covariant RouteMapPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent may swap in a fresh draft (e.g. switching which saved
    // route is being edited) without recreating this widget.
    if (_coordsDiffer(oldWidget.initialOrigin, widget.initialOrigin) ||
        _coordsDiffer(
          oldWidget.initialDestination,
          widget.initialDestination,
        )) {
      _origin = widget.initialOrigin.hasCoordinates
          ? ll.LatLng(
              widget.initialOrigin.latitude!,
              widget.initialOrigin.longitude!,
            )
          : null;
      _destination = widget.initialDestination.hasCoordinates
          ? ll.LatLng(
              widget.initialDestination.latitude!,
              widget.initialDestination.longitude!,
            )
          : null;
      if (_origin != null && _destination != null) {
        _fetchRoute();
      } else {
        setState(() => _routePoints = []);
      }
    }
  }

  // LocationPoint has no value equality, and the parent draft may
  // rebuild it on every keystroke — compare coordinates directly so a
  // routine parent rebuild doesn't reset map pan/zoom or re-fetch the
  // route needlessly.
  bool _coordsDiffer(LocationPoint a, LocationPoint b) =>
      a.latitude != b.latitude || a.longitude != b.longitude;

  void _placePoint(RouteMapEndpoint which, ll.LatLng point, {String? label}) {
    setState(() {
      if (which == RouteMapEndpoint.origin) {
        _origin = point;
        if (label != null) widget.originController.text = label;
      } else {
        _destination = point;
        if (label != null) widget.destinationController.text = label;
      }
    });
    final resolvedLabel =
        label ??
        (which == RouteMapEndpoint.origin
                ? widget.originController.text
                : widget.destinationController.text)
            .trim();
    final locationPoint = LocationPoint(
      address: resolvedLabel,
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (which == RouteMapEndpoint.origin) {
      widget.onOriginChanged(locationPoint);
    } else {
      widget.onDestinationChanged(locationPoint);
    }
    if (_origin != null && _destination != null) {
      _fetchRoute();
    } else {
      _centerOnPoints();
    }
  }

  void _onMapTap(ll.LatLng point) {
    _placePoint(_active, point);
    // After the active endpoint is placed, hop focus to whichever
    // endpoint is still unset, so tap-start/tap-end works without an
    // explicit mode switch each time.
    if (_active == RouteMapEndpoint.origin && _destination == null) {
      setState(() => _active = RouteMapEndpoint.destination);
    } else if (_active == RouteMapEndpoint.destination && _origin == null) {
      setState(() => _active = RouteMapEndpoint.origin);
    }
  }

  // Nominatim's usage policy caps this at ~1 request/second and asks
  // for an identifying User-Agent — fine for occasional manual
  // searches like this. Proxy through your own backend if search
  // volume grows.
  Future<void> _search(RouteMapEndpoint which, String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      if (which == RouteMapEndpoint.origin) {
        _searchingOrigin = true;
      } else {
        _searchingDestination = true;
      }
      _error = null;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'lk',
        'viewbox': '$_minLon,$_maxLat,$_maxLon,$_minLat',
        'bounded': '1',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'GreenYieldApp/1.0'},
      );
      final results = jsonDecode(response.body) as List;
      if (results.isEmpty) {
        setState(() => _error = 'error_location_not_found'.tr());
        return;
      }
      final result = results.first as Map<String, dynamic>;
      final point = ll.LatLng(
        double.parse(result['lat'] as String),
        double.parse(result['lon'] as String),
      );
      setState(() => _active = which);
      _placePoint(which, point, label: result['display_name'] as String);
      _mapController.move(point, 12);
    } catch (_) {
      setState(() => _error = 'error_location_unknown'.tr());
    } finally {
      if (mounted) {
        setState(() {
          _searchingOrigin = false;
          _searchingDestination = false;
        });
      }
    }
  }

  Future<void> _fetchRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;
    setState(() {
      _routing = true;
      _error = null;
    });
    try {
      // OSRM's public demo routing server — no API key, good enough
      // for previewing a real driving route on the map. Swap for a
      // self-hosted OSRM/Valhalla instance if this needs to scale.
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        setState(() => _routePoints = [origin, destination]);
        widget.onRouteInfo?.call(null, null);
        return;
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;
      setState(() {
        _routePoints = [
          for (final c in coords)
            ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        ];
      });
      final distanceKm = (route['distance'] as num).toDouble() / 1000;
      final durationMinutes = ((route['duration'] as num).toDouble() / 60)
          .round();
      widget.onRouteInfo?.call(distanceKm, durationMinutes);
    } catch (_) {
      // Routing is best-effort — fall back to a straight connector so
      // the map still shows both points linked, and let the caller's
      // own distance estimate stand in for real duration/distance.
      setState(() => _routePoints = [origin, destination]);
      widget.onRouteInfo?.call(null, null);
    } finally {
      if (mounted) setState(() => _routing = false);
      _centerOnPoints();
    }
  }

  void _centerOnPoints() {
    final points = [
      if (_origin != null) _origin!,
      if (_destination != null) _destination!,
    ];
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 12);
        return;
      }
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Roomier map on tablets/desktop web, compact on phones — the
        // picker is used inside a scroll view either way.
        final mapHeight = constraints.maxWidth >= 600 ? 340.0 : 230.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EndpointSearchField(
              icon: Icons.trip_origin,
              iconColor: theme.colorScheme.primary,
              label: 'start_location'.tr(),
              controller: widget.originController,
              isActive: _active == RouteMapEndpoint.origin,
              isSearching: _searchingOrigin,
              onTap: () => setState(() => _active = RouteMapEndpoint.origin),
              onSubmitted: (q) => _search(RouteMapEndpoint.origin, q),
            ),
            const SizedBox(height: 10),
            _EndpointSearchField(
              icon: Icons.location_on,
              iconColor: theme.colorScheme.tertiary,
              label: 'end_location'.tr(),
              controller: widget.destinationController,
              isActive: _active == RouteMapEndpoint.destination,
              isSearching: _searchingDestination,
              onTap: () =>
                  setState(() => _active = RouteMapEndpoint.destination),
              onSubmitted: (q) => _search(RouteMapEndpoint.destination, q),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (_active == RouteMapEndpoint.origin
                              ? 'tap_map_set_start'
                              : 'tap_map_set_end')
                          .tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: mapHeight,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter:
                            _origin ?? _destination ?? _srilankaCenter,
                        initialZoom: (_origin != null || _destination != null)
                            ? 10
                            : 7,
                        onTap: (_, point) => _onMapTap(point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.greenyield.app',
                        ),
                        if (_routePoints.length > 1)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _routePoints,
                                strokeWidth: 4.5,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            if (_origin != null)
                              Marker(
                                point: _origin!,
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _active = RouteMapEndpoint.origin,
                                  ),
                                  child: Icon(
                                    Icons.trip_origin,
                                    color: theme.colorScheme.primary,
                                    size: 32,
                                  ),
                                ),
                              ),
                            if (_destination != null)
                              Marker(
                                point: _destination!,
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () =>
                                        _active = RouteMapEndpoint.destination,
                                  ),
                                  child: Icon(
                                    Icons.location_on,
                                    color: theme.colorScheme.tertiary,
                                    size: 38,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (_routing)
                      const Positioned(
                        top: 10,
                        right: 10,
                        child: SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EndpointSearchField extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final TextEditingController controller;
  final bool isActive;
  final bool isSearching;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;

  const _EndpointSearchField({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.controller,
    required this.isActive,
    required this.isSearching,
    required this.onTap,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      onTap: onTap,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        suffixIcon: isSearching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.search, size: 20),
                tooltip: 'search'.tr(),
                onPressed: () => onSubmitted(controller.text),
              ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isActive ? 1.6 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
        ),
      ),
    );
  }
}
