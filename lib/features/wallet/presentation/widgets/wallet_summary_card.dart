import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../models/wallet.dart';
import '../../wallet_history.dart';
import '../../wallet_service.dart';
import '../wallet_screen.dart';

/// Balance + "View" shortcut shown on the buyer, farmer and driver profiles.
class WalletSummaryCard extends StatelessWidget {
  final String profileId;

  const WalletSummaryCard({super.key, required this.profileId});

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
                  builder: (context, snapshot) => Text(
                    walletMoney(snapshot.data?.balance ?? 0),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
