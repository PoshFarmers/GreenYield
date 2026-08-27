import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/widgets/generic_profile_info_section.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/profile.dart';
import '../farmer_profile_service.dart';
import 'farmer_profile_edit_screen.dart';

class FarmerProfileViewScreen extends ConsumerStatefulWidget {
  final Profile? initialProfile;

  const FarmerProfileViewScreen({super.key, this.initialProfile});

  @override
  ConsumerState<FarmerProfileViewScreen> createState() =>
      _FarmerProfileViewScreenState();
}

class _FarmerProfileViewScreenState
    extends ConsumerState<FarmerProfileViewScreen> {
  final _service = FarmerProfileService();

  late final Stream<Profile?> _profileStream;
  late final Stream<FarmerProfile?> _farmerProfileStream;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _farmerProfileStream = _service.watchOwnProfile(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('farmer_profile_title'.tr())),
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

          return StreamBuilder<FarmerProfile?>(
            stream: _farmerProfileStream,
            builder: (context, farmerSnapshot) {
              if (!farmerSnapshot.hasData && !farmerSnapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (farmerSnapshot.hasError) {
                return Center(child: Text(farmerSnapshot.error.toString()));
              }

              final farmerProfile = farmerSnapshot.data;
              if (farmerProfile == null) {
                return const Center(child: Text('Farmer profile not found'));
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
                          leading: const Icon(Icons.grass),
                          title: Text('crops_grown'.tr()),
                          subtitle: farmerProfile.crops.isEmpty
                              ? const Text('-')
                              : Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: farmerProfile.crops
                                        .map(
                                          (crop) =>
                                              Chip(label: Text(crop.name)),
                                        )
                                        .toList(),
                                  ),
                                ),
                        ),

                        const SizedBox(height: 24),

                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FarmerProfileEditScreen(
                                  genericProfile: profile,
                                  profile: farmerProfile,
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
