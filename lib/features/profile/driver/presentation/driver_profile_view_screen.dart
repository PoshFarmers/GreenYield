import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../models/driver_profile.dart';
import '../../../../models/profile.dart';
import '../driver_profile_service.dart';
import 'driver_profile_edit_screen.dart';

class DriverProfileViewScreen extends ConsumerStatefulWidget {
  const DriverProfileViewScreen({super.key});

  @override
  ConsumerState<DriverProfileViewScreen> createState() =>
      _DriverProfileViewScreenState();
}

class _DriverProfileViewScreenState
    extends ConsumerState<DriverProfileViewScreen> {
  final _service = DriverProfileService();
  final _avatarService = AvatarService();

  late final Stream<Profile?> _profileStream;
  late final Stream<DriverProfile?> _driverProfileStream;

  String? _avatarSignedUrl;
  String? _avatarLoadedFor;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _driverProfileStream = _service.watchOwnProfile(userId);
  }

  Future<void> _loadAvatar(String? path) async {
    if (path == null || path.isEmpty || path == _avatarLoadedFor) return;
    _avatarLoadedFor = path;

    try {
      final url = await _avatarService.signedUrl(path);
      if (mounted) {
        setState(() {
          _avatarSignedUrl = url;
        });
      }
    } catch (_) {
      // Avatar loading failure is non-fatal.
    }
  }

  String _formatAddress(Address address) {
    return [
      address.line1,
      address.line2,
      address.city,
      address.postalCode,
    ].where((value) => value != null && value.isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('driver_profile_title'.tr())),
      body: StreamBuilder<Profile?>(
        stream: _profileStream,
        builder: (context, profileSnapshot) {
          if (!profileSnapshot.hasData && !profileSnapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profileSnapshot.hasError) {
            return Center(child: Text(profileSnapshot.error.toString()));
          }

          final profile = profileSnapshot.data;

          if (profile == null) {
            return const Center(child: Text('Profile not found'));
          }

          if (profile.avatarUrl != null) {
            _loadAvatar(profile.avatarUrl);
          }

          return StreamBuilder<DriverProfile?>(
            stream: _driverProfileStream,
            builder: (context, driverSnapshot) {
              if (!driverSnapshot.hasData && !driverSnapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }

              if (driverSnapshot.hasError) {
                return Center(child: Text(driverSnapshot.error.toString()));
              }

              final driverProfile = driverSnapshot.data;
              final vehicle = driverProfile?.primaryVehicle;

              if (driverProfile == null) {
                return const Center(child: Text('Driver profile not found'));
              }

              return SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 48,
                            backgroundImage: _avatarSignedUrl != null
                                ? NetworkImage(_avatarSignedUrl!)
                                : null,
                            child: _avatarSignedUrl == null
                                ? const Icon(Icons.person, size: 48)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            '${profile.firstName} ${profile.lastName}',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ListTile(
                          leading: const Icon(Icons.phone),
                          title: Text('phone'.tr()),
                          subtitle: Text(profile.phone ?? '-'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.home),
                          title: Text('address'.tr()),
                          subtitle: Text(
                            profile.address.isEmpty
                                ? '-'
                                : _formatAddress(profile.address),
                          ),
                        ),
                        if (profile.locationText != null)
                          ListTile(
                            leading: const Icon(Icons.location_on),
                            title: Text('location'.tr()),
                            subtitle: Text(profile.locationText!),
                          ),
                        ListTile(
                          leading: const Icon(Icons.language),
                          title: Text('preferred_language'.tr()),
                          subtitle: Text(
                            profile.preferredLanguage.toUpperCase(),
                          ),
                        ),
                        const Divider(height: 32),
                        ListTile(
                          leading: const Icon(Icons.local_shipping),
                          title: Text('vehicle_type'.tr()),
                          subtitle: Text(
                            vehicle == null
                                ? '-'
                                : 'vehicle_type_${vehicle.vehicleType}'.tr(),
                          ),
                        ),
                        if (vehicle != null) ...[
                          ListTile(
                            leading: const Icon(Icons.pin),
                            title: Text('plate_number'.tr()),
                            subtitle: Text(vehicle.plateNumber),
                          ),
                          ListTile(
                            leading: const Icon(Icons.scale),
                            title: Text('max_load_kg'.tr()),
                            subtitle: Text('${vehicle.maxLoadKg}'),
                          ),
                          if (vehicle.preferredMinLoadKg != null)
                            ListTile(
                              leading: const Icon(Icons.scale_outlined),
                              title: Text('preferred_min_load_kg'.tr()),
                              subtitle: Text('${vehicle.preferredMinLoadKg}'),
                            ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DriverProfileEditScreen(
                                  profile: driverProfile,
                                ),
                              ),
                            );
                          },
                          child: Text('edit_profile'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
