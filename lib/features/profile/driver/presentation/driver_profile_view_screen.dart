import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/widgets/generic_profile_info_section.dart';
import '../../../../models/driver_profile.dart';
import '../../../../models/profile.dart';
import '../driver_profile_service.dart';
import 'driver_profile_edit_screen.dart';

class DriverProfileViewScreen extends ConsumerStatefulWidget {
  final Profile? initialProfile;

  const DriverProfileViewScreen({super.key, this.initialProfile});

  @override
  ConsumerState<DriverProfileViewScreen> createState() =>
      _DriverProfileViewScreenState();
}

class _DriverProfileViewScreenState
    extends ConsumerState<DriverProfileViewScreen> {
  final _service = DriverProfileService();

  late final Stream<Profile?> _profileStream;
  late final Stream<DriverProfile?> _driverProfileStream;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _driverProfileStream = _service.watchOwnProfile(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('driver_profile_title'.tr())),
      body: StreamBuilder<Profile?>(
        stream: _profileStream,
        initialData: widget.initialProfile,
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
                        GenericProfileInfoSection(profile: profile),

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
                                  genericProfile: profile,
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
