import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../models/farmer_profile.dart';
import '../../../../models/profile.dart';
import '../farmer_profile_service.dart';
import 'farmer_profile_edit_screen.dart';

class FarmerProfileViewScreen extends ConsumerStatefulWidget {
  const FarmerProfileViewScreen({super.key});

  @override
  ConsumerState<FarmerProfileViewScreen> createState() =>
      _FarmerProfileViewScreenState();
}

class _FarmerProfileViewScreenState
    extends ConsumerState<FarmerProfileViewScreen> {
  final _service = FarmerProfileService();
  final _avatarService = AvatarService();

  late final Stream<Profile?> _profileStream;
  late final Stream<FarmerProfile?> _farmerProfileStream;

  String? _avatarSignedUrl;
  String? _avatarLoadedFor;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _farmerProfileStream = _service.watchOwnProfile(userId);
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
      appBar: AppBar(title: Text('farmer_profile_title'.tr())),
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
