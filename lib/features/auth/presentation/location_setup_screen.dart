import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/auth/auth_providers.dart';
import '../../../core/location/location_service.dart';
import '../../../models/profile.dart';

/// Step 3 of profile setup — shared by every role, but the copy shown
/// depends on `profile.activeRole` (see the prototype: a farmer sees
/// "Farm Location" / "where your produce comes from", a driver would
/// see something about their base, etc).
///
/// Uses OpenStreetMap tiles (no API key) via flutter_map, with a
/// Nominatim text search and a "use my current location" button.
class LocationSetupScreen extends ConsumerStatefulWidget {
  const LocationSetupScreen({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<LocationSetupScreen> createState() =>
      _LocationSetupScreenState();
}

class _LocationSetupScreenState extends ConsumerState<LocationSetupScreen> {
  static const _defaultCenter = ll.LatLng(7.8731, 80.7718); // Sri Lanka

  final _mapController = MapController();
  final _searchController = TextEditingController();

  ll.LatLng? _picked;
  String _pickedLabel = '';
  bool _isSaving = false;
  bool _isSearching = false;
  bool _isLocating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _titleKey => switch (widget.profile.activeRole) {
    'farmer' => 'location_title_farmer',
    'buyer' => 'location_title_buyer',
    'driver' => 'location_title_driver',
    _ => 'location_title_default',
  };

  String get _promptKey => switch (widget.profile.activeRole) {
    'farmer' => 'location_prompt_farmer',
    'buyer' => 'location_prompt_buyer',
    'driver' => 'location_prompt_driver',
    _ => 'location_prompt_default',
  };

  void _selectPoint(ll.LatLng point, {String? label}) {
    setState(() {
      _picked = point;
      _pickedLabel =
          label ??
          '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}';
      if (label != null) _searchController.text = label;
    });
    _mapController.move(point, 15);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final result = await LocationService().fetchCurrentLocation();
      _selectPoint(
        ll.LatLng(result.point.latitude, result.point.longitude),
        label: result.displayText,
      );
    } on LocationException catch (e) {
      setState(() => _errorMessage = e.code.tr());
    } catch (e) {
      setState(() => _errorMessage = 'error_location_unknown'.tr());
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // Nominatim's usage policy caps this at ~1 request/second and asks for
  // an identifying User-Agent — fine for occasional manual searches like
  // this, but if search volume grows, proxy this through your own
  // backend instead of calling nominatim.openstreetmap.org straight
  // from the client.
  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'GreenYieldApp/1.0'},
      );
      final results = jsonDecode(response.body) as List;
      if (results.isEmpty) {
        setState(() => _errorMessage = 'error_location_not_found'.tr());
        return;
      }
      final result = results.first as Map<String, dynamic>;
      _selectPoint(
        ll.LatLng(
          double.parse(result['lat'] as String),
          double.parse(result['lon'] as String),
        ),
        label: result['display_name'] as String,
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _save() async {
    final picked = _picked;
    if (picked == null) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .updateProfileLocation(
            locationPoint: GeoPoint(
              latitude: picked.latitude,
              longitude: picked.longitude,
            ),
            locationText: _pickedLabel,
          );
      // No navigation call — AuthGate watches ownProfileProvider and
      // moves on once location_text/location_point are non-null.
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titleKey.tr(),
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: () {}),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'location_details'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'search_location_hint'.tr(),
                            prefixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.search),
                          ),
                          onSubmitted: _search,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isLocating ? null : _useCurrentLocation,
                        icon: _isLocating
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _picked ?? _defaultCenter,
                          initialZoom: _picked != null ? 15 : 7,
                          onTap: (_, point) => _selectPoint(point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.greenyield.app',
                          ),
                          if (_picked != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _picked!,
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.location_on,
                                    color: colors.error,
                                    size: 40,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _promptKey.tr(),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: (_picked == null || _isSaving) ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('continue'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
