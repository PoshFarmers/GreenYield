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

  late Future<Profile?> _profileFuture;
  late Future<FarmerProfile?> _farmerProfileFuture;

  String? _avatarSignedUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final userId = ref.read(authServiceProvider).currentUser!.id;

    _profileFuture = ref.read(authServiceProvider).fetchOwnProfile();
    _farmerProfileFuture = _service.fetchOwnProfile(userId);
  }

  Future<void> _loadAvatar(String? path) async {
    if (path == null || path.isEmpty) return;

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
      body: FutureBuilder<Profile?>(
        future: _profileFuture,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profileSnapshot.hasError) {
            return Center(child: Text(profileSnapshot.error.toString()));
          }

          final profile = profileSnapshot.data;

          if (profile == null) {
            return const Center(child: Text('Profile not found'));
          }

          // Load the avatar once the generic profile has been fetched.
          if (_avatarSignedUrl == null && profile.avatarUrl != null) {
            _loadAvatar(profile.avatarUrl);
          }

          return FutureBuilder<FarmerProfile?>(
            future: _farmerProfileFuture,
            builder: (context, farmerSnapshot) {
              if (farmerSnapshot.connectionState == ConnectionState.waiting) {
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
                        // Avatar
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

                        // Name
                        Center(
                          child: Text(
                            '${profile.firstName} ${profile.lastName}',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Phone
                        ListTile(
                          leading: const Icon(Icons.phone),
                          title: Text('phone'.tr()),
                          subtitle: Text(profile.phone ?? '-'),
                        ),

                        // Address
                        ListTile(
                          leading: const Icon(Icons.home),
                          title: Text('address'.tr()),
                          subtitle: Text(
                            profile.address.isEmpty
                                ? '-'
                                : _formatAddress(profile.address),
                          ),
                        ),

                        // Location
                        if (profile.locationText != null)
                          ListTile(
                            leading: const Icon(Icons.location_on),
                            title: Text('location'.tr()),
                            subtitle: Text(profile.locationText!),
                          ),

                        // Preferred language
                        ListTile(
                          leading: const Icon(Icons.language),
                          title: Text('preferred_language'.tr()),
                          subtitle: Text(
                            profile.preferredLanguage.toUpperCase(),
                          ),
                        ),

                        const Divider(height: 32),

                        // Crops grown
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
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => FarmerProfileEditScreen(
                                  profile: farmerProfile,
                                ),
                              ),
                            );

                            setState(_loadProfile);
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
