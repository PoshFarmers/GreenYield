import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../models/buyer_profile.dart';
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
  late Future<BuyerProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileFuture = _service.fetchOwnProfile(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('buyer_profile_title'.tr())),
      body: FutureBuilder<BuyerProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data!;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        title: Text('buyer_type'.tr()),
                        subtitle: Text(
                          profile.buyerType == 'organization'
                              ? 'buyer_type_organization'.tr()
                              : 'buyer_type_individual'.tr(),
                        ),
                      ),
                      if (profile.buyerLabel != null)
                        ListTile(
                          title: Text('buyer_label'.tr()),
                          subtitle: Text(profile.buyerLabel!),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BuyerProfileEditScreen(profile: profile),
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
            ),
          );
        },
      ),
    );
  }
}
