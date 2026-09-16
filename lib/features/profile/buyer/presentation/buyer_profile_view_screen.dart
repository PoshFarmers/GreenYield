import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/widgets/generic_profile_info_section.dart';
import '../../../../models/buyer_profile.dart';
import '../../../../models/profile.dart';
import '../../../../models/wallet.dart';
import '../buyer_profile_service.dart';
import '../../../wallet/wallet_service.dart';
import 'buyer_profile_edit_screen.dart';
import '../../../wallet/presentation/wallet_screen.dart';

class BuyerProfileViewScreen extends ConsumerStatefulWidget {
  final Profile? initialProfile;

  const BuyerProfileViewScreen({super.key, this.initialProfile});

  @override
  ConsumerState<BuyerProfileViewScreen> createState() =>
      _BuyerProfileViewScreenState();
}

class _BuyerProfileViewScreenState
    extends ConsumerState<BuyerProfileViewScreen> {
  final _service = BuyerProfileService();

  late final Stream<Profile?> _profileStream;
  late final Stream<BuyerProfile?> _buyerProfileStream;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(authServiceProvider).currentUser!.id;
    _profileStream = ref.read(authServiceProvider).watchOwnProfile();
    _buyerProfileStream = _service.watchOwnProfile(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('buyer_profile_title'.tr())),
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

          return StreamBuilder<BuyerProfile?>(
            stream: _buyerProfileStream,
            builder: (context, buyerSnapshot) {
              if (!buyerSnapshot.hasData && !buyerSnapshot.hasError) {
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
                        GenericProfileInfoSection(profile: profile),

                        _BuyerWalletCard(profileId: profile.id),
                        const SizedBox(height: 8),

                        ListTile(
                          leading: const Icon(Icons.shopping_bag),
                          title: Text('buyer_type'.tr()),
                          subtitle: Text(
                            buyerProfile.buyerType == 'organization'
                                ? 'buyer_type_organization'.tr()
                                : 'buyer_type_individual'.tr(),
                          ),
                        ),
                        if (buyerProfile.buyerLabel != null)
                          ListTile(
                            leading: const Icon(Icons.label),
                            title: Text('buyer_label'.tr()),
                            subtitle: Text(buyerProfile.buyerLabel!),
                          ),

                        const SizedBox(height: 24),

                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BuyerProfileEditScreen(
                                  genericProfile: profile,
                                  profile: buyerProfile,
                                ),
                              ),
                            );
                          },
                          child: Text('edit_profile'.tr()),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(authServiceProvider).signOut(),
                          icon: const Icon(Icons.logout),
                          label: Text('logout'.tr()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
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

class _BuyerWalletCard extends StatelessWidget {
  final String profileId;

  const _BuyerWalletCard({required this.profileId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('wallet_balance'.tr(), style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                StreamBuilder<Wallet?>(
                  stream: const WalletService().watchBalance(profileId),
                  builder: (context, snapshot) {
                    final wallet = snapshot.data;
                    final text = wallet == null
                        ? 'LKR 0.00'
                        : '${wallet.currency} ${wallet.balance.toStringAsFixed(2)}';
                    return Text(
                      text,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WalletScreen(profileId: profileId),
              ),
            ),
            child: Text('view'.tr()),
          ),
        ],
      ),
    );
  }
}
