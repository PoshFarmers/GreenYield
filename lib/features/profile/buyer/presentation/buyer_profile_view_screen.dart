import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/storage/avatar_service.dart';
import '../../../../models/buyer_profile.dart';
import '../../../../models/profile.dart';
import '../buyer_profile_service.dart';
import 'buyer_profile_edit_screen.dart';

class BuyerProfileViewScreen extends ConsumerStatefulWidget {
  const BuyerProfileViewScreen({super.key});

  @override
  ConsumerState<BuyerProfileViewScreen> createState() =>
      _BuyerProfileViewScreenState();
}

class _BuyerProfileViewScreenState
    extends ConsumerState<BuyerProfileViewScreen> {
  final _service = BuyerProfileService();
  final _avatarService = AvatarService();

  late Future<Profile?> _profileFuture;
  late Future<BuyerProfile?> _buyerProfileFuture;

  String? _avatarSignedUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final userId = ref.read(authServiceProvider).currentUser!.id;

    _profileFuture = ref.read(authServiceProvider).fetchOwnProfile();
    _buyerProfileFuture = _service.fetchOwnProfile(userId);
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
      appBar: AppBar(title: Text('buyer_profile_title'.tr())),
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

          return FutureBuilder<BuyerProfile?>(
            future: _buyerProfileFuture,
            builder: (context, buyerSnapshot) {
              if (buyerSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (buyerSnapshot.hasError) {
                return Center(child: Text(buyerSnapshot.error.toString()));
              }

              final buyerProfile = buyerSnapshot.data;

              if (buyerProfile == null) {
                return const Center(child: Text('Buyer profile not found'));
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

                        // Buyer type
                        ListTile(
                          leading: const Icon(Icons.shopping_bag),
                          title: Text('buyer_type'.tr()),
                          subtitle: Text(
                            buyerProfile.buyerType == 'organization'
                                ? 'buyer_type_organization'.tr()
                                : 'buyer_type_individual'.tr(),
                          ),
                        ),

                        // Buyer label
                        if (buyerProfile.buyerLabel != null)
                          ListTile(
                            leading: const Icon(Icons.label),
                            title: Text('buyer_label'.tr()),
                            subtitle: Text(buyerProfile.buyerLabel!),
                          ),

                        const SizedBox(height: 24),

                        ElevatedButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BuyerProfileEditScreen(
                                  profile: buyerProfile,
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
