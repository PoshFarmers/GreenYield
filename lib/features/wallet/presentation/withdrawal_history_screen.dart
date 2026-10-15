import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_secondary_header.dart';
import '../../payments/payment_gateway.dart';
import '../../payments/presentation/widgets/card_brand_icon.dart';
import '../wallet_service.dart';
import '../withdrawal_models.dart';

// Replaced by the shared money formatter in Task 15.
String _money(num value) => 'LKR ${NumberFormat('#,##0.00').format(value)}';

/// The signed-in user's withdrawals (online-only RPC read).
final withdrawalsProvider = FutureProvider.autoDispose<List<Withdrawal>>(
  (ref) => const WalletService().listWithdrawals(),
);

class WithdrawalHistoryScreen extends ConsumerWidget {
  const WithdrawalHistoryScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    try {
      ref.invalidate(withdrawalsProvider);
      await ref.read(withdrawalsProvider.future);
    } catch (_) {
      // The error state renders from the provider itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(withdrawalsProvider);

    return Scaffold(
      appBar: AppSecondaryHeader(title: 'payments_withdraw_history'.tr()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error is PaymentException
                          ? error.message
                          : 'payments_load_error'.tr(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => ref.invalidate(withdrawalsProvider),
                      icon: const Icon(Icons.refresh),
                      label: Text('payments_retry'.tr()),
                    ),
                  ],
                ),
              ),
              data: (items) => RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 56,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'payments_withdraw_history_empty'.tr(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _WithdrawalTile(item: items[index]),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  final Withdrawal item;

  const _WithdrawalTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = item.status == 'failed';
    final statusColor = switch (item.status) {
      'completed' => theme.colorScheme.primary,
      'failed' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final cardText = item.cardLast4 == null
        ? ''
        : '${item.cardBrand.label} •••• ${item.cardLast4}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CardBrandIcon(brand: item.cardBrand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _money(item.amount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cardText  ·  ${DateFormat('MMM d, yyyy, h:mm a').format(item.requestedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'payments_withdraw_failed_returned'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'payments_withdraw_status_${item.status}'.tr(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
