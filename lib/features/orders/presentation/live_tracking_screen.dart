import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_secondary_header.dart';
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

  @override
  void initState() {
    super.initState();
    // Poll every 5 seconds for live GPS updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(liveOrderTrackingProvider(widget.orderId));
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

  @override
  Widget build(BuildContext context) {
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
            if (mapPoints.length >= 2) {
              try {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(mapPoints),
                    padding: const EdgeInsets.all(60),
                  ),
                );
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
                  if (mapPoints.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: mapPoints,
                          strokeWidth: 4,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.7,
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
