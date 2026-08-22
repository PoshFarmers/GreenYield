import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'avatar_image.dart';
import '../../models/profile.dart';

/// Renders the avatar, name, phone, address, location, and preferred
/// language for [profile] — the shared header used by every role's
/// profile view screen. Role-specific content goes below it.
class GenericProfileInfoSection extends StatelessWidget {
  final Profile profile;

  const GenericProfileInfoSection({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: AvatarImage(path: profile.avatarUrl)),
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
            profile.address.isEmpty ? '-' : profile.address.formatted,
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
          subtitle: Text(profile.preferredLanguage.toUpperCase()),
        ),
        const Divider(height: 32),
      ],
    );
  }
}
